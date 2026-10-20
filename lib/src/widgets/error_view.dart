import 'package:flutter/material.dart';

/// Why the page could not be shown, in words a member of staff can act on.
@immutable
class ShellError {
  const ShellError({required this.title, required this.message, required this.icon});

  factory ShellError.network(String detail) => ShellError(
    icon: Icons.wifi_off_rounded,
    title: 'Sydwalt OS could not be reached',
    message:
        'Check that this device is online (Wi-Fi or mobile data), then try again. '
        'Files you already downloaded are still available offline.'
        '${detail.trim().isEmpty ? '' : '\n\nDetails: ${detail.trim()}'}',
  );

  factory ShellError.server(int status) => ShellError(
    icon: Icons.cloud_off_rounded,
    title: 'The server is not responding properly',
    message: status == 502 || status == 503 || status == 504
        ? 'The server may still be starting up or is being updated (HTTP $status). Wait a few seconds and try again.'
        : 'The server returned an error (HTTP $status). Try again; if it keeps happening, contact IT.',
  );

  final String title;
  final String message;
  final IconData icon;
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    required this.server,
    required this.onRetry,
    required this.onOpenDownloads,
    required this.onOpenSettings,
  });

  final ShellError error;
  final String server;
  final VoidCallback onRetry;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(error.icon, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 18),
                  Text(error.title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Text(error.message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Text(
                    server,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: onOpenDownloads,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Downloads'),
                      ),
                      TextButton.icon(
                        onPressed: onOpenSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Server settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
