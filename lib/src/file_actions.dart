import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'downloads_repository.dart';

/// Opening and sharing a saved download, with a readable message instead of a
/// silent failure when the device has no app for the file type.
class FileActions {
  static Future<void> open(BuildContext context, DownloadedFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done) return;
    final why = switch (result.type) {
      ResultType.noAppToOpen => 'No app on this device opens .${file.extension} files.',
      ResultType.fileNotFound => 'The file is no longer on this device.',
      ResultType.permissionDenied => 'The device refused access to the file.',
      _ => 'The file could not be opened (${result.message}).',
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$why Share it to another app instead?'),
          action: result.type == ResultType.fileNotFound
              ? null
              : SnackBarAction(label: 'Share', onPressed: () => share(context, file)),
        ),
      );
  }

  static Future<void> share(BuildContext context, DownloadedFile file) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: file.name, sharePositionOrigin: origin),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sharing failed: $e')));
    }
  }
}
