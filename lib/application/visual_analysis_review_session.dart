import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';
import 'visual_manual_note_placement.dart';
import 'visual_tab_analysis_service.dart';

enum VisualAnalysisRowState { waiting, analyzing, completed, failed }

/// Coordinates multi-row visual analysis without depending on Flutter.
class VisualAnalysisReviewSession {
  VisualAnalysisReviewSession({
    required this.analyzer,
    required this.strips,
    required this.sourceStringCount,
  }) : _analyses = List<VisualTabAnalysis?>.filled(strips.length, null),
       _rowStates = List<VisualAnalysisRowState>.filled(
         strips.length,
         VisualAnalysisRowState.waiting,
       );

  final VisualTabAnalyzer analyzer;
  final List<VisualStrip> strips;
  final int sourceStringCount;
  final List<VisualTabAnalysis?> _analyses;
  final List<VisualAnalysisRowState> _rowStates;
  final Map<int, Object> _rowErrors = {};
  final List<_ReviewSnapshot> _undo = [];
  final List<_ReviewSnapshot> _redo = [];
  _ReviewSnapshot? _transactionStart;
  int _currentIndex = 0;

  List<VisualTabAnalysis?> get analyses =>
      List<VisualTabAnalysis?>.unmodifiable(_analyses);
  List<VisualAnalysisRowState> get rowStates =>
      List<VisualAnalysisRowState>.unmodifiable(_rowStates);
  Map<int, Object> get rowErrors => Map<int, Object>.unmodifiable(_rowErrors);
  int get currentIndex => _currentIndex;
  int get processed => _rowStates
      .where((state) => state == VisualAnalysisRowState.completed)
      .length;
  VisualTabAnalysis get analysis => _analyses[_currentIndex]!;
  VisualTabAnalysis? get currentAnalysis =>
      _analyses.isEmpty ? null : _analyses[_currentIndex];
  bool get processingComplete =>
      _rowStates.every((state) => state == VisualAnalysisRowState.completed);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  List<int> get blockedRows => [
    for (var index = 0; index < _analyses.length; index += 1)
      if (!(_analyses[index]?.isSourceUsable ?? false)) index,
  ];

  void select(int index) => _currentIndex = index;

  void replaceCurrent(VisualTabAnalysis value, {bool recordHistory = true}) {
    if (recordHistory) _recordBeforeMutation();
    _analyses[_currentIndex] = value;
  }

  void setRiskSide(
    String systemId,
    String riskId,
    VisualConnectedComponentSide side,
  ) {
    final systems = [
      for (final system in analysis.systems)
        if (system.id != systemId)
          system
        else
          system.copyWith(
            connectedNotationRisks: [
              for (final risk in system.connectedNotationRisks)
                if (risk.id == riskId) risk.copyWith(side: side) else risk,
            ],
          ),
    ];
    replaceCurrent(analysis.copyWith(systems: systems));
  }

  void removeRisk(String systemId, String riskId) {
    final systems = [
      for (final system in analysis.systems)
        if (system.id != systemId)
          system
        else
          system.copyWith(
            connectedNotationRisks: [
              for (final risk in system.connectedNotationRisks)
                if (risk.id != riskId) risk,
            ],
          ),
    ];
    replaceCurrent(analysis.copyWith(systems: systems));
  }

  void removeTokens(Set<String> ids) {
    final systems = [
      for (final system in analysis.systems)
        system.copyWith(
          tokens: system.tokens
              .where((token) => !ids.contains(token.id))
              .toList(),
        ),
    ];
    replaceCurrent(analysis.copyWith(systems: systems));
  }

  void replaceToken(String id, VisualTabToken replacement) {
    final systems = [
      for (final system in analysis.systems)
        system.copyWith(
          tokens: [
            for (final token in system.tokens)
              if (token.id == id) replacement else token,
          ],
        ),
    ];
    replaceCurrent(analysis.copyWith(systems: systems));
  }

  void addTokenToSystem(String systemId, VisualTabToken token) {
    final systems = [
      for (final system in analysis.systems)
        if (system.id == systemId)
          system.copyWith(tokens: [...system.tokens, token])
        else
          system,
    ];
    replaceCurrent(analysis.copyWith(systems: systems));
  }

  void addTokenToNearestSystem(VisualTabToken token) {
    if (analysis.systems.isEmpty) return;
    final centerY = (token.rect.top + token.rect.bottom) / 2;
    var nearestIndex = 0;
    var distance = double.infinity;
    for (var index = 0; index < analysis.systems.length; index += 1) {
      final rect = analysis.systems[index].rect;
      final next = centerY < rect.top
          ? rect.top - centerY
          : centerY > rect.bottom
          ? centerY - rect.bottom
          : 0.0;
      if (next < distance) {
        distance = next;
        nearestIndex = index;
      }
    }
    final systems = [...analysis.systems];
    systems[nearestIndex] = systems[nearestIndex].copyWith(
      tokens: [...systems[nearestIndex].tokens, token],
    );
    replaceCurrent(analysis.copyWith(systems: systems));
  }

  VisualTabToken? addManualNote({
    required String id,
    required double x,
    required double y,
    required String text,
    required int stringIndex,
  }) {
    final placement = placeVisualManualNote(
      analysis: analysis,
      x: x,
      y: y,
      text: text,
      stringOverride: stringIndex,
    );
    if (placement == null) return null;
    final token = VisualTabToken(
      id: id,
      text: text,
      rect: placement.rect,
      kind: text == 'X' ? VisualTabTokenKind.deadNote : VisualTabTokenKind.fret,
      stringIndex: placement.stringIndex,
      confidence: 1,
      origin: VisualTabTokenOrigin.manual,
    );
    addTokenToSystem(placement.systemId, token);
    return token;
  }

  VisualTabToken? updateManualNote({
    required String id,
    required String text,
    required int stringIndex,
  }) {
    for (final system in analysis.systems) {
      final tokenIndex = system.tokens.indexWhere((token) => token.id == id);
      if (tokenIndex < 0) continue;
      final token = system.tokens[tokenIndex];
      if (token.origin != VisualTabTokenOrigin.manual) {
        continue;
      }
      final placement = placeVisualManualNote(
        analysis: analysis.copyWith(systems: [system]),
        x: (token.rect.left + token.rect.right) / 2,
        y: sourceStringLineY(system, stringIndex),
        text: text,
        stringOverride: stringIndex,
      );
      if (placement == null) return null;
      final replacement = token.copyWith(
        text: text,
        rect: placement.rect,
        kind: text == 'X'
            ? VisualTabTokenKind.deadNote
            : VisualTabTokenKind.fret,
        stringIndex: stringIndex,
      );
      replaceToken(id, replacement);
      return replacement;
    }
    return null;
  }

  bool moveManualToken(
    String id, {
    required double deltaX,
    required double deltaY,
  }) {
    for (final system in analysis.systems) {
      final tokenIndex = system.tokens.indexWhere((token) => token.id == id);
      if (tokenIndex < 0) continue;
      final token = system.tokens[tokenIndex];
      if (token.origin != VisualTabTokenOrigin.manual) return false;
      final placement = moveVisualManualNote(
        system: system,
        token: token,
        centerX: (token.rect.left + token.rect.right) / 2 + deltaX,
        centerY: (token.rect.top + token.rect.bottom) / 2 + deltaY,
      );
      final tokens = [...system.tokens];
      tokens[tokenIndex] = token.copyWith(
        rect: placement.rect,
        stringIndex: placement.stringIndex,
      );
      final systems = [
        for (final candidate in analysis.systems)
          if (candidate.id == system.id)
            candidate.copyWith(tokens: tokens)
          else
            candidate,
      ];
      replaceCurrent(analysis.copyWith(systems: systems), recordHistory: false);
      return true;
    }
    return false;
  }

  void beginTransaction() {
    _transactionStart ??= _snapshot();
  }

  void commitTransaction() {
    final start = _transactionStart;
    _transactionStart = null;
    if (start == null || _sameSnapshot(start, _snapshot())) return;
    _pushUndo(start);
  }

  void cancelTransaction() {
    final start = _transactionStart;
    _transactionStart = null;
    if (start != null) _restore(start);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _redo.add(_snapshot());
    _restore(previous);
  }

  void redo() {
    if (_redo.isEmpty) return;
    final next = _redo.removeLast();
    _pushUndo(_snapshot(), clearRedo: false);
    _restore(next);
  }

  Future<void> analyzeIndex(
    int index, {
    bool preferPositionedPdf = true,
    void Function()? onChanged,
  }) async {
    _rowStates[index] = VisualAnalysisRowState.analyzing;
    _rowErrors.remove(index);
    onChanged?.call();
    try {
      final result = await analyzer.analyze(
        strips[index],
        sourceStringCount: sourceStringCount,
        preferPositionedPdf: preferPositionedPdf,
      );
      _analyses[index] = result;
      _rowStates[index] = VisualAnalysisRowState.completed;
      if (currentAnalysis == null) _currentIndex = index;
    } catch (error) {
      _rowStates[index] = VisualAnalysisRowState.failed;
      _rowErrors[index] = error;
    }
    onChanged?.call();
  }

  Future<bool> rerunIndex(
    int index, {
    bool preferPositionedPdf = false,
    void Function()? onChanged,
  }) async {
    final before = _snapshot();
    _rowStates[index] = VisualAnalysisRowState.analyzing;
    _rowErrors.remove(index);
    onChanged?.call();
    try {
      final result = await analyzer.analyze(
        strips[index],
        sourceStringCount: sourceStringCount,
        preferPositionedPdf: preferPositionedPdf,
      );
      _analyses[index] = _preserveManualTokens(_analyses[index], result);
      _rowStates[index] = VisualAnalysisRowState.completed;
      _pushUndo(before);
      onChanged?.call();
      return true;
    } catch (error) {
      _restore(before);
      _rowErrors[index] = error;
      onChanged?.call();
      return false;
    }
  }

  Future<bool> rerunAll({void Function()? onChanged}) async {
    final before = _snapshot();
    final next = <VisualTabAnalysis?>[..._analyses];
    var failedIndex = before.currentIndex;
    try {
      for (var index = 0; index < strips.length; index += 1) {
        failedIndex = index;
        _rowStates[index] = VisualAnalysisRowState.analyzing;
        _rowErrors.remove(index);
        onChanged?.call();
        final result = await analyzer.analyze(
          strips[index],
          sourceStringCount: sourceStringCount,
          preferPositionedPdf: false,
        );
        next[index] = _preserveManualTokens(_analyses[index], result);
        _rowStates[index] = VisualAnalysisRowState.completed;
      }
      for (var index = 0; index < next.length; index += 1) {
        _analyses[index] = next[index];
      }
      _currentIndex = before.currentIndex;
      _pushUndo(before);
      onChanged?.call();
      return true;
    } catch (error) {
      _restore(before);
      _rowErrors[failedIndex] = error;
      onChanged?.call();
      return false;
    }
  }

  void _recordBeforeMutation() {
    if (_transactionStart != null) return;
    _pushUndo(_snapshot());
  }

  void _pushUndo(_ReviewSnapshot snapshot, {bool clearRedo = true}) {
    _undo.add(snapshot);
    if (_undo.length > 50) _undo.removeAt(0);
    if (clearRedo) _redo.clear();
  }

  _ReviewSnapshot _snapshot() => _ReviewSnapshot(
    analyses: [..._analyses],
    rowStates: [..._rowStates],
    rowErrors: {..._rowErrors},
    currentIndex: _currentIndex,
  );

  void _restore(_ReviewSnapshot snapshot) {
    for (var index = 0; index < _analyses.length; index += 1) {
      _analyses[index] = snapshot.analyses[index];
      _rowStates[index] = snapshot.rowStates[index];
    }
    _rowErrors
      ..clear()
      ..addAll(snapshot.rowErrors);
    _currentIndex = snapshot.currentIndex.clamp(0, _analyses.length - 1);
  }

  bool _sameSnapshot(_ReviewSnapshot left, _ReviewSnapshot right) {
    if (left.currentIndex != right.currentIndex) return false;
    for (var index = 0; index < left.analyses.length; index += 1) {
      if (left.analyses[index]?.toJson().toString() !=
          right.analyses[index]?.toJson().toString()) {
        return false;
      }
    }
    return true;
  }
}

class _ReviewSnapshot {
  const _ReviewSnapshot({
    required this.analyses,
    required this.rowStates,
    required this.rowErrors,
    required this.currentIndex,
  });

  final List<VisualTabAnalysis?> analyses;
  final List<VisualAnalysisRowState> rowStates;
  final Map<int, Object> rowErrors;
  final int currentIndex;
}

VisualTabAnalysis _preserveManualTokens(
  VisualTabAnalysis? previous,
  VisualTabAnalysis rerun,
) {
  if (previous == null) return rerun;
  final manual = <(VisualTabSystem, VisualTabToken)>[
    for (final system in previous.systems)
      for (final token in system.tokens)
        if (token.origin == VisualTabTokenOrigin.manual) (system, token),
  ];
  if (manual.isEmpty || rerun.systems.isEmpty) return rerun;
  final systems = [...rerun.systems];
  for (final entry in manual) {
    final sourceSystem = entry.$1;
    final manualToken = entry.$2;
    var targetIndex = systems.indexWhere(
      (system) => system.id == sourceSystem.id,
    );
    if (targetIndex < 0) {
      final centerY = (manualToken.rect.top + manualToken.rect.bottom) / 2;
      var bestDistance = double.infinity;
      for (var index = 0; index < systems.length; index += 1) {
        final systemCenter =
            (systems[index].rect.top + systems[index].rect.bottom) / 2;
        final distance = (systemCenter - centerY).abs();
        if (distance < bestDistance) {
          targetIndex = index;
          bestDistance = distance;
        }
      }
    }
    if (targetIndex < 0) continue;
    final target = systems[targetIndex];
    final tokens = [
      for (final token in target.tokens)
        if (!_overlapsManualCorrection(token, manualToken)) token,
      manualToken,
    ];
    systems[targetIndex] = target.copyWith(tokens: tokens);
  }
  return rerun.copyWith(systems: systems);
}

bool _overlapsManualCorrection(VisualTabToken detected, VisualTabToken manual) {
  if (detected.origin == VisualTabTokenOrigin.manual ||
      detected.stringIndex != manual.stringIndex ||
      !detected.isFretLike) {
    return false;
  }
  final horizontalOverlap =
      detected.rect.left < manual.rect.right &&
      detected.rect.right > manual.rect.left;
  final verticalOverlap =
      detected.rect.top < manual.rect.bottom &&
      detected.rect.bottom > manual.rect.top;
  if (horizontalOverlap && verticalOverlap) return true;
  final detectedCenter = (detected.rect.left + detected.rect.right) / 2;
  final manualCenter = (manual.rect.left + manual.rect.right) / 2;
  return (detectedCenter - manualCenter).abs() <=
      (detected.rect.width + manual.rect.width) / 2;
}
