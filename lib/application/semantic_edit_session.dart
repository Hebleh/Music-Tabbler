import 'dart:async';

import '../domain/music_models.dart';

class SemanticUndoHistory {
  SemanticUndoHistory({this.maximumEntries = 50});

  final int maximumEntries;
  final List<String> _snapshots = [];

  bool get canUndo => _snapshots.isNotEmpty;

  void record(SongChart chart) {
    _snapshots.add(chart.encode());
    if (_snapshots.length > maximumEntries) _snapshots.removeAt(0);
  }

  SongChart? undo() =>
      _snapshots.isEmpty ? null : SongChart.decode(_snapshots.removeLast());
}

class DebouncedSemanticAutosaver {
  DebouncedSemanticAutosaver({
    required this.save,
    this.delay = const Duration(milliseconds: 650),
    this.onError,
  });

  final Future<void> Function(SongChart chart) save;
  final Duration delay;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  SongChart? _pending;
  Future<void>? _drainFuture;

  void schedule(SongChart chart) {
    _pending = chart;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final active = _drainFuture;
    if (active != null) return active.then((_) => flush());
    if (_pending == null) return Future.value();
    final future = _drain();
    _drainFuture = future.whenComplete(() => _drainFuture = null);
    return _drainFuture!;
  }

  Future<void> _drain() async {
    while (true) {
      final chart = _pending;
      if (chart == null) break;
      _pending = null;
      try {
        await save(chart);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await flush();
  }
}
