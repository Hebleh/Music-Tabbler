class RecognitionFixtureManifest {
  const RecognitionFixtureManifest({
    required this.id,
    required this.rightsBasis,
    required this.expectedSystems,
    required this.expectedMeasures,
    required this.expectedStrings,
    required this.expectedFrets,
    required this.expectedRhythmEvents,
    required this.expectedLyrics,
  });

  final String id;
  final String rightsBasis;
  final int expectedSystems;
  final int expectedMeasures;
  final int expectedStrings;
  final List<int> expectedFrets;
  final int expectedRhythmEvents;
  final List<String> expectedLyrics;

  void validateForPublicCorpus() {
    if (id.trim().isEmpty) {
      throw const FormatException('Recognition fixture ID cannot be blank.');
    }
    if (rightsBasis != 'synthetic' && rightsBasis != 'self-authored') {
      throw const FormatException(
        'Public recognition fixtures must be synthetic or self-authored.',
      );
    }
    if (expectedSystems < 1 ||
        expectedMeasures < 1 ||
        expectedStrings < 1 ||
        expectedFrets.any((fret) => fret < 0 || fret > 36)) {
      throw const FormatException(
        'Recognition fixture annotations are invalid.',
      );
    }
  }
}

class RecognitionMetrics {
  const RecognitionMetrics({
    required this.structureRecall,
    required this.fretAccuracy,
    required this.rhythmAccuracy,
    required this.lyricAccuracy,
    required this.correctionCost,
  });

  final double structureRecall;
  final double fretAccuracy;
  final double rhythmAccuracy;
  final double lyricAccuracy;

  /// Number of insert/delete/change actions required to match ground truth.
  final int correctionCost;
}

RecognitionMetrics measureRecognition({
  required RecognitionFixtureManifest expected,
  required int detectedSystems,
  required int detectedMeasures,
  required int detectedStrings,
  required List<int> detectedFrets,
  required int detectedRhythmEvents,
  required List<String> detectedLyrics,
}) {
  expected.validateForPublicCorpus();
  final expectedStructures =
      expected.expectedSystems +
      expected.expectedMeasures +
      expected.expectedStrings;
  final matchedStructures =
      detectedSystems.clamp(0, expected.expectedSystems) +
      detectedMeasures.clamp(0, expected.expectedMeasures) +
      detectedStrings.clamp(0, expected.expectedStrings);
  final fretDistance = _editDistance(expected.expectedFrets, detectedFrets);
  final lyricDistance = _editDistance(
    expected.expectedLyrics.map(_normalizeLyric).toList(),
    detectedLyrics.map(_normalizeLyric).toList(),
  );
  final rhythmDistance = (expected.expectedRhythmEvents - detectedRhythmEvents)
      .abs();
  return RecognitionMetrics(
    structureRecall: matchedStructures / expectedStructures,
    fretAccuracy: _accuracy(expected.expectedFrets.length, fretDistance),
    rhythmAccuracy: _accuracy(expected.expectedRhythmEvents, rhythmDistance),
    lyricAccuracy: _accuracy(expected.expectedLyrics.length, lyricDistance),
    correctionCost: fretDistance + lyricDistance + rhythmDistance,
  );
}

double _accuracy(int expectedCount, int distance) {
  if (expectedCount == 0) return distance == 0 ? 1 : 0;
  return (1 - distance / expectedCount).clamp(0, 1);
}

String _normalizeLyric(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _editDistance<T>(List<T> left, List<T> right) {
  var prior = List<int>.generate(right.length + 1, (index) => index);
  for (var row = 1; row <= left.length; row += 1) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = row;
    for (var column = 1; column <= right.length; column += 1) {
      final substitution =
          prior[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1);
      current[column] = [
        prior[column] + 1,
        current[column - 1] + 1,
        substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    prior = current;
  }
  return prior.last;
}
