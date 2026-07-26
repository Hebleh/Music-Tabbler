import '../domain/music_models.dart';
import 'recognition_review.dart';

class PitchTranspositionResult {
  const PitchTranspositionResult({
    required this.chart,
    required this.semitones,
    required this.movedStrings,
  });

  final SongChart chart;
  final int semitones;
  final int movedStrings;
}

class UnplayableTransformationException implements Exception {
  const UnplayableTransformationException(this.messages);

  final List<String> messages;

  @override
  String toString() => messages.join(' ');
}

class PitchTranspositionService {
  const PitchTranspositionService();

  PitchTranspositionResult transpose({
    required SongChart source,
    required int semitones,
    required String derivedChartId,
  }) {
    if (semitones == 0 || semitones < -24 || semitones > 24) {
      throw const FormatException(
        'Transpose by a non-zero interval from -24 to +24 semitones.',
      );
    }
    final unresolved = unresolvedProposalCount(source);
    if (unresolved > 0) {
      throw StateError(
        'Verify all $unresolved recognition proposal(s) before transposing.',
      );
    }
    final validation = source.validationErrors();
    if (validation.isNotEmpty) {
      throw StateError(
        'Fix chart validation errors before transposing: '
        '${validation.join(' ')}',
      );
    }

    final errors = <String>[];
    var movedStrings = 0;
    final measures = <ChartMeasure>[];
    for (final (measureIndex, measure) in source.measures.indexed) {
      final notes = <TabNote>[];
      for (final note in measure.notes) {
        final targetPitch =
            note.midiPitch(source.tuning, capo: source.capo) + semitones;
        final placement = _placePitch(
          targetPitch,
          tuning: source.tuning,
          capo: source.capo,
          preferredString: note.stringIndex,
          preferredFret: note.fret + semitones,
        );
        if (placement == null) {
          errors.add(
            'Measure ${measureIndex + 1}, note ${note.id}: pitch $targetPitch '
            'is not playable on ${source.tuning.name}.',
          );
          continue;
        }
        if (placement.$1 != note.stringIndex) movedStrings += 1;
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
    final sign = semitones > 0 ? '+' : '';
    return PitchTranspositionResult(
      chart: source.copyWith(
        id: derivedChartId,
        title: '${source.title} ($sign$semitones)',
        measures: List.unmodifiable(measures),
        gigReady: false,
        derivedFromChartId: source.id,
        transformationLabel: 'Transpose $sign$semitones',
      ),
      semitones: semitones,
      movedStrings: movedStrings,
    );
  }

  (int, int)? _placePitch(
    int midiPitch, {
    required BassTuning tuning,
    required int capo,
    required int preferredString,
    required int preferredFret,
  }) {
    if (preferredString >= 0 &&
        preferredString < tuning.strings.length &&
        preferredFret >= 0 &&
        preferredFret <= 36 &&
        tuning.strings[preferredString].midiPitch + preferredFret + capo ==
            midiPitch) {
      return (preferredString, preferredFret);
    }
    final candidates = <(int, int)>[];
    for (final (index, string) in tuning.strings.indexed) {
      final fret = midiPitch - string.midiPitch - capo;
      if (fret >= 0 && fret <= 36) candidates.add((index, fret));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final stringDistanceA = (a.$1 - preferredString).abs();
      final stringDistanceB = (b.$1 - preferredString).abs();
      final stringComparison = stringDistanceA.compareTo(stringDistanceB);
      if (stringComparison != 0) return stringComparison;
      return a.$2.compareTo(b.$2);
    });
    return candidates.first;
  }
}
