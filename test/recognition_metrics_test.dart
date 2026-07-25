import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/recognition_metrics.dart';

void main() {
  const fixture = RecognitionFixtureManifest(
    id: 'synthetic-five-string-01',
    rightsBasis: 'synthetic',
    expectedSystems: 1,
    expectedMeasures: 2,
    expectedStrings: 5,
    expectedFrets: [3, 3, 5, 1],
    expectedRhythmEvents: 4,
    expectedLyrics: ['hello', 'world'],
  );

  test('rights-safe recognition manifest and exact metrics validate', () {
    fixture.validateForPublicCorpus();
    final result = measureRecognition(
      expected: fixture,
      detectedSystems: 1,
      detectedMeasures: 2,
      detectedStrings: 5,
      detectedFrets: const [3, 3, 5, 1],
      detectedRhythmEvents: 4,
      detectedLyrics: const ['Hello', 'world'],
    );
    expect(result.structureRecall, 1);
    expect(result.fretAccuracy, 1);
    expect(result.rhythmAccuracy, 1);
    expect(result.lyricAccuracy, 1);
    expect(result.correctionCost, 0);
  });

  test('metrics expose correction cost instead of hiding misses', () {
    final result = measureRecognition(
      expected: fixture,
      detectedSystems: 1,
      detectedMeasures: 1,
      detectedStrings: 5,
      detectedFrets: const [3, 8, 1],
      detectedRhythmEvents: 3,
      detectedLyrics: const ['hello'],
    );
    expect(result.structureRecall, lessThan(1));
    expect(result.fretAccuracy, lessThan(1));
    expect(result.correctionCost, greaterThan(0));
  });

  test('copyright-ambiguous public fixtures are rejected', () {
    const invalid = RecognitionFixtureManifest(
      id: 'site-capture',
      rightsBasis: 'downloaded-site-tab',
      expectedSystems: 1,
      expectedMeasures: 1,
      expectedStrings: 4,
      expectedFrets: [],
      expectedRhythmEvents: 0,
      expectedLyrics: [],
    );
    expect(invalid.validateForPublicCorpus, throwsFormatException);
  });
}
