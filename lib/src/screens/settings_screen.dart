import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../link_policy.dart';
import '../settings_store.dart';

enum _Check { idle, running, ok, failed }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.onClearWebData, this.httpClient});

  final SettingsStore settings;
  final Future<void> Function() onClearWebData;
  final http.Client? httpClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(text: widget.settings.serverUrl);
  String? _urlError;
  _Check _check = _Check.idle;
  String _checkMessage = '';
  bool _saving = false;
  bool _clearing = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) => mounted ? setState(() => _version = '${info.version} (${info.buildNumber})') : null)
        .catchError((Object _) => null);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  bool get _dirty => LinkPolicy.normaliseServerUrl(_url.text) != widget.settings.serverUrl;

  /// Calls the server's /healthz endpoint, the same one Fly.io uses.
  Future<bool> _testConnection() async {
    final error = LinkPolicy.validateServerUrl(_url.text);
    setState(() => _urlError = error);
    if (error != null) return false;
    setState(() {
      _check = _Check.running;
      _checkMessage = 'Contacting the server…';
    });
    final base = LinkPolicy.normaliseServerUrl(_url.text);
    final client = widget.httpClient ?? http.Client();
    try {
      final res = await client.get(Uri.parse('$base/healthz')).timeout(const Duration(seconds: 20));
      final ok = res.statusCode == 200;
      if (mounted) {
        setState(() {
          _check = ok ? _Check.ok : _Check.failed;
          _checkMessage = ok
              ? 'Connected. The server is running.'
              : 'The server answered with HTTP ${res.statusCode}. Check the address.';
        });
      }
      return ok;
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _check = _Check.failed;
          _checkMessage = 'No answer within 20 seconds. Check the address and your connection.';
        });
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() {
          _check = _Check.failed;
          _checkMessage = 'Could not connect: $e';
        });
      }
      return false;
    } finally {
      if (widget.httpClient == null) client.close();
    }
  }

  Future<void> _save() async {
    final error = LinkPolicy.validateServerUrl(_url.text);
    setState(() => _urlError = error);
    if (error != null) return;
    setState(() => _saving = true);
    final reachable = await _testConnection();
    if (!mounted) return;
    if (!reachable) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Server not reachable'),
          content: const Text('The app could not reach that address just now. Save it anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    await widget.settings.setServerUrl(_url.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _url.text = widget.settings.serverUrl;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Server address saved. Sydwalt OS is reloading.')));
  }

  Future<void> _reset() async {
    await widget.settings.resetServerUrl();
    if (!mounted) return;
    setState(() {
      _url.text = widget.settings.serverUrl;
      _urlError = null;
      _check = _Check.idle;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Back to the standard Sydwalt OS server.')));
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out and clear app data?'),
        content: const Text(
          'This signs you out and removes everything Sydwalt OS stored in the app on this device, '
          'including any changes made offline that have not synced to the server yet.\n\n'
          'Your Downloads folder is not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out and clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await widget.onClearWebData();
      messenger.showSnackBar(const SnackBar(content: Text('Signed out. App data on this device was cleared.')));
      nav.pop();
    } catch (e) {
      if (mounted) setState(() => _clearing = false);
      messenger.showSnackBar(SnackBar(content: Text('Clearing failed: $e. Try again, or reinstall the app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _clearing,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Server', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Only change this if IT asks you to, for example to try a test server.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Server address',
                hintText: 'https://sydwalt-os.fly.dev',
                border: const OutlineInputBorder(),
                errorText: _urlError,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() {
                _urlError = null;
                _check = _Check.idle;
              }),
            ),
            if (_check != _Check.idle)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    switch (_check) {
                      _Check.running => const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      _Check.ok => Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                      _ => Icon(Icons.error, color: theme.colorScheme.error, size: 20),
                    },
                    const SizedBox(width: 8),
                    Expanded(child: Text(_checkMessage)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _check == _Check.running ? null : _testConnection,
                  child: const Text('Test connection'),
                ),
                FilledButton(onPressed: _saving || !_dirty ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
                if (!widget.settings.isDefaultServer)
                  TextButton(onPressed: _reset, child: const Text('Use the standard server')),
              ],
            ),
            const Divider(height: 40),
            Text('This device', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _clearing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.logout, color: theme.colorScheme.error),
              title: const Text('Sign out and clear app data'),
              subtitle: const Text('Use this before handing the device to someone else.'),
              onTap: _clear,
            ),
            const Divider(height: 40),
            Text('About', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Sydwalt OS app${_version.isEmpty ? '' : ' $_version'}'),
            Text('Standard server: ${AppConfig.defaultServerUrl}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('For access problems contact IT: siphesihle@sydwalt.co.za', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
