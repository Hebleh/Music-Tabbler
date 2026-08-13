import '../domain/visual_tab_transform_models.dart';

class ParsedVisualTuning {
  const ParsedVisualTuning({required this.labels, required this.openMidis});

  final List<String> labels;
  final List<int> openMidis;
}

ParsedVisualTuning parseVisualTuningSpec(String value) {
  final labels = <String>[];
  final midis = <int>[];
  for (final raw in value.split(',')) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    final separator = part.lastIndexOf(':');
    if (separator <= 0 || separator == part.length - 1) {
      throw const FormatException(
        'Use comma-separated label:MIDI strings, for example E:28, A:33.',
      );
    }
    final label = part.substring(0, separator).trim();
    final midi = int.tryParse(part.substring(separator + 1).trim());
    if (label.isEmpty || midi == null || midi < 0 || midi > 127) {
      throw const FormatException(
        'Every string needs a label and MIDI pitch from 0 to 127.',
      );
    }
    labels.add(label);
    midis.add(midi);
  }
  if (!isSupportedVisualTabStringCount(labels.length)) {
    throw const FormatException('A tuning needs 2 to 12 strings.');
  }
  for (var index = 1; index < midis.length; index += 1) {
    if (midis[index] <= midis[index - 1]) {
      throw const FormatException(
        'Enter strings low to high with rising MIDI pitches.',
      );
    }
  }
  return ParsedVisualTuning(
    labels: List.unmodifiable(labels),
    openMidis: List.unmodifiable(midis),
  );
}

Map<int, int> parseSelectedStringPitchChanges(
  String value, {
  required int sourceStringCount,
}) {
  if (value.trim().isEmpty) return const {};
  final result = <int, int>{};
  for (final raw in value.split(',')) {
    final part = raw.trim();
    final separator = part.indexOf(':');
    if (separator <= 0 || separator == part.length - 1) {
      throw const FormatException(
        'Use source-string:change entries, for example 1:+3, 4:-1.',
      );
    }
    final oneBasedString = int.tryParse(part.substring(0, separator).trim());
    final change = int.tryParse(part.substring(separator + 1).trim());
    if (oneBasedString == null ||
        oneBasedString < 1 ||
        oneBasedString > sourceStringCount ||
        change == null ||
        change < -24 ||
        change > 24) {
      throw const FormatException(
        'Selected strings must exist and pitch changes must be -24 to +24.',
      );
    }
    result[oneBasedString - 1] = change;
  }
  return Map.unmodifiable(result);
}
