import 'package:flutter/material.dart';

import '../transfers.dart';

/// A strip at the bottom of the screen listing downloads in progress, with a
/// real percentage when the size is known and a moving bar when it is not.
class TransferBanner extends StatelessWidget {
  const TransferBanner({super.key, required this.tracker});

  final TransferTracker tracker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final items = tracker.active;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: items.isEmpty
              ? const SizedBox.shrink()
              : Material(
                  key: const ValueKey('transfers'),
                  elevation: 6,
                  color: Theme.of(context).colorScheme.inverseSurface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final t in items.take(3)) _Row(t: t)],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.t});
  final Transfer t;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onInverseSurface;
    final pct = t.progress == null ? '' : '  ${(t.progress! * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Downloading ${t.name}$pct',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: on, fontSize: 13),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: t.progress,
            minHeight: 3,
            color: on,
            backgroundColor: on.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}
