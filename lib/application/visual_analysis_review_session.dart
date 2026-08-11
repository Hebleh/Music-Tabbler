import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';
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
  List<int> get blockedRows => [
    for (var index = 0; index < _analyses.length; index += 1)
      if (!(_analyses[index]?.isSourceUsable ?? false)) index,
  ];

  void select(int index) => _currentIndex = index;

  void replaceCurrent(VisualTabAnalysis value) {
    _analyses[_currentIndex] = value;
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
}
