import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/visual_tuning_parser.dart';

void main() {
  test('parses arbitrary low-to-high tuning', () {
    final tuning = parseVisualTuningSpec('D#:27, G#:32, C#:37, F#:42');
    expect(tuning.labels, ['D#', 'G#', 'C#', 'F#']);
    expect(tuning.openMidis, [27, 32, 37, 42]);
  });

  test('rejects tuning not entered low to high', () {
    expect(
      () => parseVisualTuningSpec('G:43, D:38, A:33, E:28'),
      throwsFormatException,
    );
  });

  test('parses selected-string pitch overrides as zero-based keys', () {
    expect(
      parseSelectedStringPitchChanges('1:+3, 4:-1', sourceStringCount: 4),
      {0: 3, 3: -1},
    );
  });
}
