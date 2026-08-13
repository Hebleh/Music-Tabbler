import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/visual_analysis_review_session.dart';
import 'package:music_tabbler/application/visual_tab_analysis_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';

void main() {
  test('review session coordinates completion, failure, and retry', () async {
    final analyzer = _Analyzer();
    final session = VisualAnalysisReviewSession(
      analyzer: analyzer,
      strips: const [
        VisualStrip(
          id: 'good',
          assetHash: 'a',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
        VisualStrip(
          id: 'retry',
          assetHash: 'b',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
      ],
      sourceStringCount: 4,
    );

    await session.analyzeIndex(0);
    await session.analyzeIndex(1);

    expect(session.processed, 1);
    expect(session.processingComplete, isFalse);
    expect(session.rowStates[1], VisualAnalysisRowState.failed);
    expect(session.rowErrors[1], isA<StateError>());

    await session.analyzeIndex(1, preferPositionedPdf: false);

    expect(session.processed, 2);
    expect(session.processingComplete, isTrue);
    expect(session.blockedRows, isEmpty);
    expect(analyzer.preferences, [true, true, false]);
  });

  test(
    'review history supports undo redo and bounded grouped transactions',
    () async {
      final session = VisualAnalysisReviewSession(
        analyzer: _Analyzer(),
        strips: const [
          VisualStrip(
            id: 'good',
            assetHash: 'a',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 20,
          ),
        ],
        sourceStringCount: 4,
      );
      await session.analyzeIndex(0);
      final original = session.analysis;

      session.beginTransaction();
      session.replaceCurrent(
        original.copyWith(warnings: const ['drag preview 1']),
        recordHistory: false,
      );
      session.replaceCurrent(
        original.copyWith(warnings: const ['drag preview 2']),
        recordHistory: false,
      );
      session.commitTransaction();

      expect(session.canUndo, isTrue);
      expect(session.analysis.warnings, ['drag preview 2']);
      session.undo();
      expect(session.analysis.warnings, isEmpty);
      expect(session.canRedo, isTrue);
      session.redo();
      expect(session.analysis.warnings, ['drag preview 2']);

      session.undo();
      session.replaceCurrent(original.copyWith(warnings: const ['new branch']));
      expect(session.canRedo, isFalse);
    },
  );

  test(
    'manual note commands add drag cancel remove and undo atomically',
    () async {
      final session = VisualAnalysisReviewSession(
        analyzer: _Analyzer(),
        strips: const [
          VisualStrip(
            id: 'good',
            assetHash: 'a',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 20,
          ),
        ],
        sourceStringCount: 4,
      );
      await session.analyzeIndex(0);
      final manual = session.addManualNote(
        id: 'manual',
        x: 0.6,
        y: 0.8,
        text: '12',
        stringIndex: 0,
      );
      expect(manual, isNotNull);
      expect(manual!.origin, VisualTabTokenOrigin.manual);
      expect(manual.stringIndex, 0);

      session.beginTransaction();
      expect(
        session.moveManualToken('manual', deltaX: 0.1, deltaY: -0.4),
        isTrue,
      );
      session.commitTransaction();
      final moved = session.analysis.systems.single.tokens.singleWhere(
        (token) => token.id == 'manual',
      );
      expect(moved.stringIndex, 2);
      expect((moved.rect.left + moved.rect.right) / 2, closeTo(0.7, 0.001));
      session.undo();
      final restored = session.analysis.systems.single.tokens.singleWhere(
        (token) => token.id == 'manual',
      );
      expect(restored.stringIndex, 0);
      expect(
        (restored.rect.left + restored.rect.right) / 2,
        closeTo(0.6, 0.001),
      );

      session.beginTransaction();
      session.moveManualToken('manual', deltaX: -0.2, deltaY: -0.2);
      session.cancelTransaction();
      expect(
        session.analysis.systems.single.tokens
            .singleWhere((token) => token.id == 'manual')
            .toJson(),
        restored.toJson(),
      );

      session.removeTokens({'manual'});
      expect(
        session.analysis.systems.single.tokens.any(
          (token) => token.id == 'manual',
        ),
        isFalse,
      );
      session.undo();
      expect(
        session.analysis.systems.single.tokens.any(
          (token) => token.id == 'manual',
        ),
        isTrue,
      );
    },
  );

  test(
    'OCR rerun preserves manual corrections and is one undo action',
    () async {
      final analyzer = _Analyzer();
      final session = VisualAnalysisReviewSession(
        analyzer: analyzer,
        strips: const [
          VisualStrip(
            id: 'good',
            assetHash: 'a',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 20,
          ),
        ],
        sourceStringCount: 4,
      );
      await session.analyzeIndex(0);
      final system = session.analysis.systems.single;
      const manual = VisualTabToken(
        id: 'manual',
        text: '(7)',
        rect: NormalizedRect(0.4, 0.5, 0.45, 0.6),
        kind: VisualTabTokenKind.fret,
        stringIndex: 2,
        origin: VisualTabTokenOrigin.manual,
      );
      session.replaceCurrent(
        session.analysis.copyWith(
          systems: [
            system.copyWith(tokens: [...system.tokens, manual]),
          ],
        ),
      );
      final beforeRerun = session.analysis;

      expect(await session.rerunIndex(0), isTrue);
      final tokens = session.analysis.systems.single.tokens;
      expect(
        tokens.where((token) => token.origin == VisualTabTokenOrigin.manual),
        [manual],
      );
      expect(
        tokens.where((token) => token.origin == VisualTabTokenOrigin.detected),
        isEmpty,
      );
      session.undo();
      expect(session.analysis.toJson(), beforeRerun.toJson());
    },
  );

  test(
    'failed OCR rerun changes no reviewed content and adds no history',
    () async {
      final analyzer = _AlwaysFailOnRerunAnalyzer();
      final session = VisualAnalysisReviewSession(
        analyzer: analyzer,
        strips: const [
          VisualStrip(
            id: 'good',
            assetHash: 'a',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 20,
          ),
        ],
        sourceStringCount: 4,
      );
      await session.analyzeIndex(0);
      final before = session.analysis.toJson();
      expect(await session.rerunIndex(0), isFalse);
      expect(session.analysis.toJson(), before);
      expect(session.canUndo, isFalse);
    },
  );

  test('all-row OCR rerun is atomic and preserves the selected row', () async {
    final analyzer = _FailSecondRowOnRerunAnalyzer();
    final session = VisualAnalysisReviewSession(
      analyzer: analyzer,
      strips: const [
        VisualStrip(
          id: 'first',
          assetHash: 'a',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
        VisualStrip(
          id: 'second',
          assetHash: 'b',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
      ],
      sourceStringCount: 4,
    );
    await session.analyzeIndex(0);
    await session.analyzeIndex(1);
    session.select(0);
    final before = session.analyses.map((value) => value!.toJson()).toList();

    expect(await session.rerunAll(), isFalse);
    expect(session.analyses.map((value) => value!.toJson()).toList(), before);
    expect(session.currentIndex, 0);
    expect(session.rowErrors, contains(1));
    expect(session.canUndo, isFalse);

    analyzer.fail = false;
    expect(await session.rerunAll(), isTrue);
    expect(session.currentIndex, 0);
    expect(session.canUndo, isTrue);
    session.undo();
    expect(session.analyses.map((value) => value!.toJson()).toList(), before);
  });

  test('review history retains only the latest fifty transactions', () async {
    final session = VisualAnalysisReviewSession(
      analyzer: _Analyzer(),
      strips: const [
        VisualStrip(
          id: 'good',
          assetHash: 'a',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
      ],
      sourceStringCount: 4,
    );
    await session.analyzeIndex(0);
    for (var index = 0; index < 55; index += 1) {
      session.replaceCurrent(
        session.analysis.copyWith(warnings: ['change $index']),
      );
    }

    for (var index = 0; index < 50; index += 1) {
      expect(session.canUndo, isTrue);
      session.undo();
    }
    expect(session.canUndo, isFalse);
    expect(session.analysis.warnings, ['change 4']);
  });
}

class _Analyzer implements VisualTabAnalyzer {
  final List<bool> preferences = [];
  var failedOnce = false;

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    preferences.add(preferPositionedPdf);
    if (strip.id == 'retry' && !failedOnce) {
      failedOnce = true;
      throw StateError('retry me');
    }
    return VisualTabAnalysis(
      stripId: strip.id,
      sourceType: VisualTabSourceType.rasterOcr,
      systems: const [
        VisualTabSystem(
          id: 'system',
          rect: NormalizedRect(0, 0, 1, 1),
          stringLines: [0.2, 0.4, 0.6, 0.8],
          tokens: [
            VisualTabToken(
              id: 'token',
              text: '3',
              rect: NormalizedRect(0.4, 0.5, 0.45, 0.6),
              kind: VisualTabTokenKind.fret,
              stringIndex: 2,
            ),
          ],
        ),
      ],
    );
  }
}

class _AlwaysFailOnRerunAnalyzer extends _Analyzer {
  var calls = 0;

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    calls += 1;
    if (calls > 1) throw StateError('rerun failed');
    return super.analyze(
      strip,
      sourceStringCount: sourceStringCount,
      preferPositionedPdf: preferPositionedPdf,
    );
  }
}

class _FailSecondRowOnRerunAnalyzer extends _Analyzer {
  final Map<String, int> callsByStrip = {};
  bool fail = true;

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    final calls = (callsByStrip[strip.id] ?? 0) + 1;
    callsByStrip[strip.id] = calls;
    if (fail && strip.id == 'second' && calls > 1) {
      throw StateError('second row rerun failed');
    }
    return super.analyze(
      strip,
      sourceStringCount: sourceStringCount,
      preferPositionedPdf: preferPositionedPdf,
    );
  }
}
