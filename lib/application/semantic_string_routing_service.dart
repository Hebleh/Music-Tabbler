import '../domain/music_models.dart';
import 'pitch_transposition_service.dart';
import 'recognition_review.dart';

class SemanticStringRoutingResult {
  const SemanticStringRoutingResult({
    required this.chart,
    required this.routedNotes,
    required this.pitchChangedNotes,
    required this.diagnostics,
  });

  final SongChart chart;
  final int routedNotes;
  final int pitchChangedNotes;
  final List<String> diagnostics;
}

class SemanticStringRoutingService {
  const SemanticStringRoutingService();

  SemanticStringRoutingResult transform({
    required SongChart source,
    required BassTuning targetTuning,
    required int targetCapo,
    required int globalPitchChange,
    required String derivedChartId,
    Map<int, int> selectedStringPitchChanges = const {},
    Map<int, int> routeConstraints = const {},
  }) {
    if (targetCapo < 0 || targetCapo > 24) {
      throw const FormatException('Target capo must be between 0 and 24.');
    }
    if (globalPitchChange < -24 || globalPitchChange > 24) {
      throw const FormatException('Pitch change must be -24 to +24.');
    }
    if (targetTuning.strings.length < 2 || targetTuning.strings.length > 12) {
      throw const FormatException('Target tuning needs 2 to 12 strings.');
    }
    final unresolved = unresolvedProposalCount(source);
    if (unresolved > 0) {
      throw StateError(
        'Verify all $unresolved recognition proposal(s) before routing.',
      );
    }
    final validation = source.validationErrors();
    if (validation.isNotEmpty) {
      throw StateError(
        'Fix chart validation errors before routing: ${validation.join(' ')}',
      );
    }
    for (final entry in selectedStringPitchChanges.entries) {
      if (entry.key < 0 ||
          entry.key >= source.tuning.strings.length ||
          entry.value < -24 ||
          entry.value > 24) {
        throw const FormatException(
          'Selected-string pitch changes must reference source strings and '
          'stay between -24 and +24.',
        );
      }
    }
    for (final entry in routeConstraints.entries) {
      if (entry.key < 0 ||
          entry.key >= source.tuning.strings.length ||
          entry.value < 0 ||
          entry.value >= targetTuning.strings.length) {
        throw const FormatException(
          'String route constraints must reference existing strings.',
        );
      }
    }

    final errors = <String>[];
    final diagnostics = <String>[];
    final measures = <ChartMeasure>[];
    var routedNotes = 0;
    var pitchChangedNotes = 0;
    for (final (measureIndex, measure) in source.measures.indexed) {
      final notes = <TabNote>[];
      for (final note in measure.notes) {
        final pitchChange =
            selectedStringPitchChanges[note.stringIndex] ?? globalPitchChange;
        final sourcePitch = note.midiPitch(source.tuning, capo: source.capo);
        final targetPitch = sourcePitch + pitchChange;
        final constrainedTarget = routeConstraints[note.stringIndex];
        final placement = constrainedTarget == null
            ? _automaticPlacement(
                targetPitch,
                targetTuning: targetTuning,
                targetCapo: targetCapo,
                preferredString: note.stringIndex,
                preferredFret: note.fret,
              )
            : _constrainedPlacement(
                targetPitch,
                targetTuning: targetTuning,
                targetCapo: targetCapo,
                targetString: constrainedTarget,
              );
        if (placement == null) {
          errors.add(
            'Measure ${measureIndex + 1}, note ${note.id}: pitch $targetPitch '
            'is not playable on ${targetTuning.name}'
            '${constrainedTarget == null ? "" : " using target string ${constrainedTarget + 1}"}.',
          );
          continue;
        }
        final finalPitch =
            targetTuning.strings[placement.$1].midiPitch +
            placement.$2 +
            targetCapo;
        if (finalPitch != targetPitch) {
          errors.add(
            'Measure ${measureIndex + 1}, note ${note.id}: routed pitch '
            '$finalPitch does not match requested pitch $targetPitch.',
          );
          continue;
        }
        if (placement.$1 != note.stringIndex) routedNotes += 1;
        if (pitchChange != 0) pitchChangedNotes += 1;
        notes.add(
          note.copyWith(
            stringIndex: placement.$1,
            fret: placement.$2,
            verification: VerificationState.verified,
            clearConfidence: true,
            clearSourceMapping: true,
          ),
        );
      }
      measures.add(measure.copyWith(notes: List.unmodifiable(notes)));
    }
    if (errors.isNotEmpty) {
      throw UnplayableTransformationException(List.unmodifiable(errors));
    }
    if (selectedStringPitchChanges.isNotEmpty) {
      diagnostics.add(
        '${selectedStringPitchChanges.length} source string(s) use explicit '
        'pitch-change overrides.',
      );
    }
    if (routeConstraints.isNotEmpty) {
      diagnostics.add(
        '${routeConstraints.length} source string route(s) are constrained.',
      );
    }
    final sign = globalPitchChange >= 0 ? '+' : '';
    return SemanticStringRoutingResult(
      chart: source.copyWith(
        id: derivedChartId,
        title:
            '${source.title} (${targetTuning.name}, $sign$globalPitchChange)',
        tuning: targetTuning,
        capo: targetCapo,
        measures: List.unmodifiable(measures),
        gigReady: false,
        derivedFromChartId: source.id,
        transformationLabel:
            'Route strings: $sign$globalPitchChange, capo $targetCapo',
      ),
      routedNotes: routedNotes,
      pitchChangedNotes: pitchChangedNotes,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  (int, int)? _constrainedPlacement(
    int targetPitch, {
    required BassTuning targetTuning,
    required int targetCapo,
    required int targetString,
  }) {
    final fret =
        targetPitch - targetTuning.strings[targetString].midiPitch - targetCapo;
    return fret >= 0 && fret <= 36 ? (targetString, fret) : null;
  }

  (int, int)? _automaticPlacement(
    int targetPitch, {
    required BassTuning targetTuning,
    required int targetCapo,
    required int preferredString,
    required int preferredFret,
  }) {
    final candidates = <(int, int)>[];
    for (final (index, string) in targetTuning.strings.indexed) {
      final fret = targetPitch - string.midiPitch - targetCapo;
      if (fret >= 0 && fret <= 36) candidates.add((index, fret));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      final leftCost =
          (left.$1 - preferredString).abs() * 100 +
          (left.$2 - preferredFret).abs();
      final rightCost =
          (right.$1 - preferredString).abs() * 100 +
          (right.$2 - preferredFret).abs();
      final cost = leftCost.compareTo(rightCost);
      if (cost != 0) return cost;
      return left.$2.compareTo(right.$2);
    });
    return candidates.first;
  }
}
