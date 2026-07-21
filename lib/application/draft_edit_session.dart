import 'dart:async';

import '../domain/visual_chart_models.dart';

class DraftUndoHistory {
  DraftUndoHistory({this.maximumEntries = 50});

  final int maximumEntries;
  final List<String> _snapshots = [];

  bool get canUndo => _snapshots.isNotEmpty;
  int get length => _snapshots.length;

  void record(VisualChartDraft draft) {
    _snapshots.add(draft.encode());
    if (_snapshots.length > maximumEntries) _snapshots.removeAt(0);
  }

  VisualChartDraft? undo() {
    if (_snapshots.isEmpty) return null;
    return VisualChartDraft.decode(_snapshots.removeLast());
  }
}

class DebouncedDraftAutosaver {
  DebouncedDraftAutosaver({
    required this.save,
    this.delay = const Duration(milliseconds: 650),
    this.onError,
  });

  final Future<void> Function(VisualChartDraft draft) save;
  final Duration delay;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  VisualChartDraft? _pending;
  Future<void>? _drainFuture;

  void schedule(VisualChartDraft draft) {
    _pending = draft;
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
      final draft = _pending;
      if (draft == null) break;
      _pending = null;
      try {
        await save(draft);
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
