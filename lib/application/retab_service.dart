import '../domain/music_models.dart';
import 'pitch_transposition_service.dart';
import 'recognition_review.dart';

enum RetabStrategy { preserveShape, lowPosition, minimumMovement, minimumSpan }

extension RetabStrategyLabel on RetabStrategy {
  String get label => switch (this) {
    RetabStrategy.preserveShape => 'Preserve strings and shapes',
    RetabStrategy.lowPosition => 'Prefer low frets',
    RetabStrategy.minimumMovement => 'Minimize position changes',
    RetabStrategy.minimumSpan => 'Minimize fret span',
  };
}

class RetabResult {
  const RetabResult({
    required this.chart,
    required this.strategy,
    required this.score,
    required this.explanation,
  });

  final SongChart chart;
  final RetabStrategy strategy;
  final double score;
  final String explanation;
}

class RetabService {
  const RetabService();

  List<RetabResult> rankedVariants({
    required SongChart source,
    required BassTuning targetTuning,
    required String idPrefix,
  }) {
    final distinct = <String, RetabResult>{};
    for (final strategy in RetabStrategy.values) {
      final result = retab(
        source: source,
        targetTuning: targetTuning,
        derivedChartId: '$idPrefix-${strategy.name}',
        strategy: strategy,
      );
      final signature = [
        for (final measure in result.chart.measures)
          for (final note in measure.notes) '${note.stringIndex}:${note.fret}',
      ].join(',');
      distinct.putIfAbsent(signature, () => result);
    }
    final ranked = distinct.values.toList()
      ..sort((a, b) {
        final score = a.score.compareTo(b.score);
        return score != 0
            ? score
            : a.strategy.index.compareTo(b.strategy.index);
      });
    return List.unmodifiable(ranked);
  }

  RetabResult retab({
    required SongChart source,
    required BassTuning targetTuning,
    required String derivedChartId,
    RetabStrategy strategy = RetabStrategy.preserveShape,
  }) {
    final unresolved = unresolvedProposalCount(source);
    if (unresolved > 0) {
      throw StateError(
        'Verify all $unresolved recognition proposal(s) before re-tabbing.',
      );
    }
    if (source.validationErrors().isNotEmpty) {
      throw StateError('Fix chart validation errors before re-tabbing.');
    }
    if (targetTuning.strings.isEmpty) {
      throw const FormatException(
        'The target tuning needs at least one string.',
      );
    }

    final failures = <String>[];
    final measures = <ChartMeasure>[];
    final allFrets = <int>[];
    var priorFret = 0;
    var movement = 0;
    var stringChanges = 0;
    for (final (measureIndex, measure) in source.measures.indexed) {
      final notes = <TabNote>[];
      for (final note in measure.notes) {
        final pitch = note.midiPitch(source.tuning, capo: source.capo);
        final candidates = _candidates(targetTuning, pitch, capo: source.capo);
        if (candidates.isEmpty) {
          failures.add(
            'Measure ${measureIndex + 1}, note ${note.id}: pitch $pitch is not '
            'playable on ${targetTuning.name}.',
          );
          continue;
        }
        final selected = _select(
          candidates,
          strategy: strategy,
          originalString: note.stringIndex,
          originalFret: note.fret,
          priorFret: priorFret,
          runningFrets: allFrets,
        );
        movement += (selected.$2 - priorFret).abs();
        if (selected.$1 != note.stringIndex) stringChanges += 1;
        priorFret = selected.$2;
        allFrets.add(selected.$2);
        notes.add(
          note.copyWith(
            stringIndex: selected.$1,
            fret: selected.$2,
            verification: VerificationState.verified,
            clearConfidence: true,
            clearSourceMapping: true,
          ),
        );
      }
      measures.add(measure.copyWith(notes: List.unmodifiable(notes)));
    }
    if (failures.isNotEmpty) {
      throw UnplayableTransformationException(List.unmodifiable(failures));
    }
    final minimumFret = allFrets.isEmpty
        ? 0
        : allFrets.reduce((a, b) => a < b ? a : b);
    final maximumFret = allFrets.isEmpty
        ? 0
        : allFrets.reduce((a, b) => a > b ? a : b);
    final span = maximumFret - minimumFret;
    final score = movement + span * 2 + stringChanges * 1.5;
    return RetabResult(
      chart: source.copyWith(
        id: derivedChartId,
        title: '${source.title} (${targetTuning.name})',
        tuning: targetTuning,
        measures: List.unmodifiable(measures),
        gigReady: false,
        derivedFromChartId: source.id,
        transformationLabel: 'Retab: ${strategy.label}',
      ),
      strategy: strategy,
      score: score,
      explanation:
          '${strategy.label}: movement $movement, fret span $span, '
          'string changes $stringChanges.',
    );
  }

  List<(int, int)> _candidates(
    BassTuning tuning,
    int midiPitch, {
    required int capo,
  }) {
    final result = <(int, int)>[];
    for (final (index, string) in tuning.strings.indexed) {
      final fret = midiPitch - string.midiPitch - capo;
      if (fret >= 0 && fret <= 36) result.add((index, fret));
    }
    return result;
  }

  (int, int) _select(
    List<(int, int)> candidates, {
    required RetabStrategy strategy,
    required int originalString,
    required int originalFret,
    required int priorFret,
    required List<int> runningFrets,
  }) {
    num cost((int, int) candidate) {
      final stringDelta = (candidate.$1 - originalString).abs();
      final shapeDelta = (candidate.$2 - originalFret).abs();
      final positionMovement = (candidate.$2 - priorFret).abs();
      final nextFrets = [...runningFrets, candidate.$2];
      final min = nextFrets.reduce((a, b) => a < b ? a : b);
      final max = nextFrets.reduce((a, b) => a > b ? a : b);
      return switch (strategy) {
        RetabStrategy.preserveShape =>
          stringDelta * 1000 + shapeDelta * 5 + positionMovement,
        RetabStrategy.lowPosition =>
          candidate.$2 * 8 + positionMovement + stringDelta,
        RetabStrategy.minimumMovement =>
          positionMovement * 10 + stringDelta * 2 + candidate.$2 * 0.1,
        RetabStrategy.minimumSpan =>
          (max - min) * 10 + positionMovement + stringDelta,
      };
    }

    final ordered = [...candidates]
      ..sort((a, b) {
        final compared = cost(a).compareTo(cost(b));
        if (compared != 0) return compared;
        final fret = a.$2.compareTo(b.$2);
        return fret != 0 ? fret : a.$1.compareTo(b.$1);
      });
    return ordered.first;
  }
}
