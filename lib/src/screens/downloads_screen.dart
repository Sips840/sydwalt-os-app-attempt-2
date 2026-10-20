import 'dart:async';

import 'package:flutter/material.dart';

import '../date_labels.dart';
import '../downloads_repository.dart';
import '../file_actions.dart';
import '../file_naming.dart';

/// Every file the app has saved: search by name, filter by date, then open,
/// share, rename or delete (with undo).
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.repository, this.clock = DateTime.now});

  final DownloadsRepository repository;
  final DateTime Function() clock;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  DateFilter _filter = DateFilter.all;
  List<DownloadedFile>? _files;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repository.removeListener(_load);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final files = await widget.repository.list(query: _search.text, since: _filter.since(widget.clock()));
      if (!mounted) return;
      setState(() {
        _files = files;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _load);
    setState(() {}); // Shows or hides the clear button immediately.
  }

  Future<void> _delete(DownloadedFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final token = await widget.repository.delete(file);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Deleted ${file.name}'),
            action: SnackBarAction(label: 'Undo', onPressed: () => widget.repository.restore(token)),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete ${file.name}: $e')));
    }
  }

  Future<void> _rename(DownloadedFile file) async {
    final controller = TextEditingController(text: file.name);
    final dot = file.name.lastIndexOf('.');
    controller.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : file.name.length);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Rename')),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final renamed = await widget.repository.rename(file, newName);
      messenger.showSnackBar(SnackBar(content: Text('Renamed to ${renamed.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not rename: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search downloads by name',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final f in DateFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'The Downloads folder could not be read',
        body: '$_loadError',
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    final files = _files;
    if (files == null) return const Center(child: CircularProgressIndicator());
    if (files.isEmpty) {
      final filtered = _search.text.isNotEmpty || _filter != DateFilter.all;
      return _Message(
        icon: filtered ? Icons.search_off : Icons.download_outlined,
        title: filtered ? 'Nothing matches' : 'No downloads yet',
        body: filtered
            ? 'Try another name or a wider date range.'
            : 'Exports from Sydwalt OS (CSV logs, Word reports, payment batches, documents) are saved here, '
                  'so you can open or share them again later, even offline.',
      );
    }
    final now = widget.clock();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: files.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final f = files[i];
          return ListTile(
            leading: Icon(_iconFor(f.extension)),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${DateLabels.describe(f.modified, now)} · ${FileNaming.formatSize(f.size)}'),
            onTap: () => FileActions.open(context, f),
            trailing: PopupMenuButton<String>(
              tooltip: 'File actions',
              onSelected: (v) {
                switch (v) {
                  case 'open':
                    FileActions.open(context, f);
                  case 'share':
                    FileActions.share(context, f);
                  case 'rename':
                    _rename(f);
                  case 'delete':
                    _delete(f);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'share', child: Text('Share or save to…')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          );
        },
      ),
    );
  }

  static IconData _iconFor(String ext) => switch (ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'csv' || 'xlsx' || 'xls' => Icons.table_chart_outlined,
    'doc' || 'docx' || 'md' || 'txt' => Icons.description_outlined,
    'png' || 'jpg' || 'jpeg' => Icons.image_outlined,
    'json' => Icons.data_object,
    'zip' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
