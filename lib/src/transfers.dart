import 'package:flutter/foundation.dart';

/// A download in flight, shown in the progress banner at the bottom of the
/// shell. [progress] is null while the size is unknown (exports built in the
/// page), which shows an indeterminate bar.
@immutable
class Transfer {
  const Transfer({required this.id, required this.name, this.progress});

  final int id;
  final String name;
  final double? progress;

  Transfer withProgress(double? p) => Transfer(id: id, name: name, progress: p);
}

class TransferTracker extends ChangeNotifier {
  final Map<int, Transfer> _active = {};
  int _next = 1;

  List<Transfer> get active => List.unmodifiable(_active.values);
  bool get isBusy => _active.isNotEmpty;

  int start(String name) {
    final id = _next++;
    _active[id] = Transfer(id: id, name: name.isEmpty ? 'file' : name);
    notifyListeners();
    return id;
  }

  void update(int id, double? progress) {
    final t = _active[id];
    if (t == null) return;
    _active[id] = t.withProgress(progress?.clamp(0.0, 1.0));
    notifyListeners();
  }

  void finish(int id) {
    if (_active.remove(id) != null) notifyListeners();
  }
}
