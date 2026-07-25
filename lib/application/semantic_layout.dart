import '../domain/music_models.dart';

enum SemanticTextRole {
  title,
  metadata,
  measureNumber,
  fret,
  lyric,
  backingLyric,
  section,
  technique,
  rest,
}

enum SemanticLineRole { staff, tab, bar, rhythm, repeat }

sealed class SemanticPrimitive {
  const SemanticPrimitive();
}

class SemanticLinePrimitive extends SemanticPrimitive {
  const SemanticLinePrimitive({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.role,
    this.width = 1,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final SemanticLineRole role;
  final double width;
}

class SemanticTextPrimitive extends SemanticPrimitive {
  const SemanticTextPrimitive({
    required this.text,
    required this.x,
    required this.y,
    required this.role,
    required this.size,
  });

  final String text;
  final double x;
  final double y;
  final SemanticTextRole role;
  final double size;
}

class SemanticEllipsePrimitive extends SemanticPrimitive {
  const SemanticEllipsePrimitive({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class SemanticNoteTarget {
  const SemanticNoteTarget({
    required this.noteId,
    required this.x,
    required this.y,
  });

  final String noteId;
  final double x;
  final double y;
}

class SemanticLayoutPlan {
  const SemanticLayoutPlan({
    required this.width,
    required this.height,
    required this.primitives,
    required this.noteTargets,
    required this.systemTops,
  });

  final double width;
  final double height;
  final List<SemanticPrimitive> primitives;
  final List<SemanticNoteTarget> noteTargets;
  final List<double> systemTops;

  List<({double start, double end})> paginate(double maximumHeight) {
    if (systemTops.isEmpty) return [(start: 0, end: height)];
    final ranges = <({double start, double end})>[];
    var start = 0.0;
    for (var index = 0; index < systemTops.length; index += 1) {
      final next = index + 1 < systemTops.length
          ? systemTops[index + 1]
          : height;
      if (next - start > maximumHeight && systemTops[index] > start) {
        ranges.add((start: start, end: systemTops[index]));
        start = systemTops[index];
      }
    }
    ranges.add((start: start, end: height));
    return ranges;
  }
}

class SemanticLayoutEngine {
  const SemanticLayoutEngine({this.width = 1000, this.measuresPerSystem = 4});

  final double width;
  final int measuresPerSystem;

  SemanticLayoutPlan build(
    SongChart chart, {
    required bool showTitle,
    required bool showTab,
    required bool showNotation,
  }) {
    const margin = 34.0;
    const musicTop = 76.0;
    final primitives = <SemanticPrimitive>[];
    final targets = <SemanticNoteTarget>[];
    final systemTops = <double>[];
    if (showTitle) {
      primitives.add(
        SemanticTextPrimitive(
          text: chart.title,
          x: margin,
          y: 18,
          role: SemanticTextRole.title,
          size: 22,
        ),
      );
      if (chart.artist.trim().isNotEmpty) {
        primitives.add(
          SemanticTextPrimitive(
            text: chart.artist,
            x: margin,
            y: 46,
            role: SemanticTextRole.metadata,
            size: 12,
          ),
        );
      }
    }
    final systemHeight =
        48 +
        (showNotation ? 76 : 0) +
        (showTab ? chart.tuning.strings.length * 20 + 58 : 0);
    final systemCount = (chart.measures.length / measuresPerSystem).ceil();
    for (var system = 0; system < systemCount; system += 1) {
      final start = system * measuresPerSystem;
      final end = (start + measuresPerSystem).clamp(0, chart.measures.length);
      final count = end - start;
      final top = musicTop + system * systemHeight;
      systemTops.add(top);
      final measureWidth = (width - margin * 2) / count;
      final section = chart.sections
          .where((item) => item.measureIndex == start)
          .firstOrNull;
      if (section != null) {
        primitives.add(
          SemanticTextPrimitive(
            text: section.name,
            x: margin,
            y: top,
            role: SemanticTextRole.section,
            size: 13,
          ),
        );
      }
      final notationTop = top + 28;
      final tabTop = notationTop + (showNotation ? 76 : 0);
      if (showNotation) {
        for (var line = 0; line < 5; line += 1) {
          primitives.add(
            SemanticLinePrimitive(
              x1: margin,
              y1: notationTop + line * 9,
              x2: width - margin,
              y2: notationTop + line * 9,
              role: SemanticLineRole.staff,
            ),
          );
        }
      }
      if (showTab) {
        for (
          var stringIndex = 0;
          stringIndex < chart.tuning.strings.length;
          stringIndex += 1
        ) {
          final y = tabTop + stringIndex * 20;
          primitives
            ..add(
              SemanticTextPrimitive(
                text: chart.tuning.strings[stringIndex].name,
                x: 12,
                y: y - 7,
                role: SemanticTextRole.metadata,
                size: 10,
              ),
            )
            ..add(
              SemanticLinePrimitive(
                x1: margin,
                y1: y,
                x2: width - margin,
                y2: y,
                role: SemanticLineRole.tab,
              ),
            );
        }
      }
      for (var local = 0; local < count; local += 1) {
        final measureIndex = start + local;
        final measure = chart.measures[measureIndex];
        final left = margin + local * measureWidth;
        primitives.add(
          SemanticTextPrimitive(
            text: measure.number.toString(),
            x: left + 4,
            y: top + 8,
            role: SemanticTextRole.measureNumber,
            size: 10,
          ),
        );
        if (showTab) {
          primitives.add(
            SemanticLinePrimitive(
              x1: left,
              y1: tabTop,
              x2: left,
              y2: tabTop + (chart.tuning.strings.length - 1) * 20,
              role: SemanticLineRole.bar,
              width: local == 0 ? 1.5 : 1,
            ),
          );
        }
        for (final note in measure.notes) {
          final x =
              left +
              (note.position.value + 0.5) / measure.length.value * measureWidth;
          if (showNotation) {
            final midi = note.midiPitch(chart.tuning, capo: chart.capo);
            final y = (notationTop + 44 - (midi - 28) * 1.55).clamp(
              notationTop - 8,
              notationTop + 56,
            );
            primitives
              ..add(SemanticEllipsePrimitive(x: x, y: y, width: 10, height: 7))
              ..add(
                SemanticLinePrimitive(
                  x1: x + 4,
                  y1: y,
                  x2: x + 4,
                  y2: y - 21,
                  role: SemanticLineRole.rhythm,
                  width: 1.3,
                ),
              );
          }
          if (showTab) {
            final y = tabTop + note.stringIndex * 20;
            targets.add(SemanticNoteTarget(noteId: note.id, x: x, y: y));
            primitives.add(
              SemanticTextPrimitive(
                text: note.fret.toString(),
                x: x - 4,
                y: y - 7,
                role: SemanticTextRole.fret,
                size: 12,
              ),
            );
            for (var index = 0; index < note.techniques.length; index += 1) {
              primitives.add(
                SemanticTextPrimitive(
                  text: _techniqueLabel(note.techniques[index]),
                  x: x + 8 + index * 12,
                  y: y - 7,
                  role: SemanticTextRole.technique,
                  size: 9,
                ),
              );
            }
          }
        }
        for (final rest in measure.rests) {
          final x =
              left +
              (rest.position.value + 0.5) / measure.length.value * measureWidth;
          primitives.add(
            SemanticTextPrimitive(
              text: 'R',
              x: x,
              y: showNotation ? notationTop + 14 : tabTop - 18,
              role: SemanticTextRole.rest,
              size: 11,
            ),
          );
        }
        if (showTab) {
          final lyricY = tabTop + chart.tuning.strings.length * 20 + 8;
          for (final lyric in chart.lyrics.where(
            (lyric) => lyric.measureIndex == measureIndex,
          )) {
            final x =
                left +
                (lyric.position.value + 0.5) /
                    measure.length.value *
                    measureWidth;
            primitives.add(
              SemanticTextPrimitive(
                text: lyric.text,
                x: x - lyric.text.length * 3,
                y: lyricY,
                role: lyric.isBackingVocal
                    ? SemanticTextRole.backingLyric
                    : SemanticTextRole.lyric,
                size: lyric.isBackingVocal ? 12 : 10,
              ),
            );
          }
        }
      }
      if (showTab) {
        primitives.add(
          SemanticLinePrimitive(
            x1: width - margin,
            y1: tabTop,
            x2: width - margin,
            y2: tabTop + (chart.tuning.strings.length - 1) * 20,
            role: SemanticLineRole.bar,
            width: 1.5,
          ),
        );
      }
    }
    return SemanticLayoutPlan(
      width: width,
      height: musicTop + systemCount * systemHeight,
      primitives: List.unmodifiable(primitives),
      noteTargets: List.unmodifiable(targets),
      systemTops: List.unmodifiable(systemTops),
    );
  }

  String _techniqueLabel(TechniqueMark mark) => switch (mark.kind) {
    TechniqueKind.slide => '/',
    TechniqueKind.bend => 'b',
    TechniqueKind.hammerOn => 'h',
    TechniqueKind.pullOff => 'p',
    TechniqueKind.naturalHarmonic => '<>',
    TechniqueKind.artificialHarmonic => 'AH',
    TechniqueKind.deadNote => 'x',
    TechniqueKind.palmMute => 'PM',
    TechniqueKind.letRing => 'LR',
    TechniqueKind.accent => '>',
  };
}
