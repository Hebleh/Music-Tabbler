import 'package:xml/xml.dart';

import '../domain/music_models.dart';

class MusicXmlDiagnostic {
  const MusicXmlDiagnostic(this.message, {this.isLoss = false});

  final String message;
  final bool isLoss;
}

class MusicXmlImportResult {
  const MusicXmlImportResult({required this.chart, required this.diagnostics});

  final SongChart chart;
  final List<MusicXmlDiagnostic> diagnostics;
}

class MusicXmlExportResult {
  const MusicXmlExportResult({required this.xml, required this.diagnostics});

  final String xml;
  final List<MusicXmlDiagnostic> diagnostics;
}

/// A deliberately bounded MusicXML 4.0 interchange boundary.
///
/// It supports one bass part, exact note/rest rhythm, tablature positions,
/// lyrics, time signatures, tempo, tunings, repeats, endings, and the technique
/// subset represented by [TechniqueKind]. Unsupported constructs are reported
/// instead of being silently treated as supported.
class MusicXmlService {
  const MusicXmlService();

  MusicXmlExportResult exportChart(SongChart chart) {
    final diagnostics = <MusicXmlDiagnostic>[];
    final divisions = _requiredDivisions(chart);
    final builder = XmlBuilder();
    builder
      ..processing('xml', 'version="1.0" encoding="UTF-8"')
      ..element(
        'score-partwise',
        attributes: {'version': '4.0'},
        nest: () {
          builder
            ..element(
              'work',
              nest: () => builder.element('work-title', nest: chart.title),
            )
            ..element(
              'identification',
              nest: () => builder.element(
                'creator',
                attributes: {'type': 'composer'},
                nest: chart.artist,
              ),
            )
            ..element(
              'part-list',
              nest: () => builder.element(
                'score-part',
                attributes: {'id': 'P1'},
                nest: () =>
                    builder.element('part-name', nest: chart.instrumentName),
              ),
            )
            ..element(
              'part',
              attributes: {'id': 'P1'},
              nest: () {
                for (var index = 0; index < chart.measures.length; index += 1) {
                  final measure = chart.measures[index];
                  builder.element(
                    'measure',
                    attributes: {'number': '${measure.number}'},
                    nest: () {
                      _writeMeasureAttributes(
                        builder,
                        chart,
                        measure,
                        divisions,
                        includeTuning: index == 0,
                      );
                      if (measure.tempoBpm case final tempo?) {
                        builder.element(
                          'direction',
                          nest: () {
                            builder
                              ..element(
                                'direction-type',
                                nest: () => builder.element(
                                  'metronome',
                                  nest: () {
                                    builder
                                      ..element('beat-unit', nest: 'quarter')
                                      ..element('per-minute', nest: '$tempo');
                                  },
                                ),
                              )
                              ..element(
                                'sound',
                                attributes: {'tempo': '$tempo'},
                              );
                          },
                        );
                      }
                      _writeDirections(builder, chart, index);
                      _writeEvents(builder, chart, index, divisions);
                      _writeBarlines(builder, chart, index);
                    },
                  );
                }
              },
            );
        },
      );
    return MusicXmlExportResult(
      xml: builder.buildDocument().toXmlString(pretty: true),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  MusicXmlImportResult importChart(String source) {
    final diagnostics = <MusicXmlDiagnostic>[];
    final document = XmlDocument.parse(source);
    final root = document.rootElement;
    if (root.name.local != 'score-partwise') {
      throw const FormatException('Only score-partwise MusicXML is supported.');
    }
    final parts = root.findElements('part').toList();
    if (parts.isEmpty) {
      throw const FormatException('The MusicXML file has no part.');
    }
    if (parts.length > 1) {
      diagnostics.add(
        const MusicXmlDiagnostic(
          'Only the first MusicXML part was imported.',
          isLoss: true,
        ),
      );
    }
    final part = parts.first;
    var divisions = 1;
    var time = const TimeSignature(4, 4);
    var tuning = BassTuning.eadg;
    final measures = <ChartMeasure>[];
    final lyrics = <LyricSyllable>[];
    final sections = <SongSection>[];
    final repeats = <RepeatRegion>[];
    int? pendingRepeatStart;

    for (final (measureIndex, measureElement)
        in part.findElements('measure').indexed) {
      final attributes = measureElement.getElement('attributes');
      if (attributes != null) {
        divisions =
            int.tryParse(attributes.getElement('divisions')?.innerText ?? '') ??
            divisions;
        final timeElement = attributes.getElement('time');
        if (timeElement != null) {
          time = TimeSignature(
            int.parse(timeElement.getElement('beats')!.innerText),
            int.parse(timeElement.getElement('beat-type')!.innerText),
          );
        }
        if (measureIndex == 0) {
          tuning = _readTuning(attributes, diagnostics);
        }
      }
      final notes = <TabNote>[];
      final rests = <RestEvent>[];
      var cursor = BeatFraction.zero;
      var noteOrdinal = 0;
      for (final child in measureElement.children.whereType<XmlElement>()) {
        if (child.name.local == 'backup' || child.name.local == 'forward') {
          diagnostics.add(
            const MusicXmlDiagnostic(
              'Backup/forward voice positioning is not imported yet.',
              isLoss: true,
            ),
          );
          continue;
        }
        if (child.name.local != 'note') continue;
        final durationTicks =
            int.tryParse(child.getElement('duration')?.innerText ?? '') ?? 0;
        final duration = BeatFraction(durationTicks, divisions);
        final value = _noteValueFor(duration, diagnostics);
        final voice =
            int.tryParse(child.getElement('voice')?.innerText ?? '') ?? 1;
        final isChord = child.getElement('chord') != null;
        final position = isChord && notes.isNotEmpty
            ? notes.last.position
            : cursor;
        final id = 'mx-${measureIndex + 1}-${noteOrdinal++}';
        if (child.getElement('rest') != null) {
          rests.add(
            RestEvent(id: id, position: position, value: value, voice: voice),
          );
        } else {
          final technical = child
              .getElement('notations')
              ?.getElement('technical');
          final stringNumber = int.tryParse(
            technical?.getElement('string')?.innerText ?? '',
          );
          final fret = int.tryParse(
            technical?.getElement('fret')?.innerText ?? '',
          );
          final pitch = _readMidiPitch(child.getElement('pitch'));
          final placement = _placeNote(
            tuning,
            pitch,
            stringNumber: stringNumber,
            fret: fret,
          );
          notes.add(
            TabNote.exact(
              id: id,
              position: position,
              stringIndex: placement.$1,
              fret: placement.$2,
              value: value,
              voice: voice,
              techniques: _readTechniques(child),
            ),
          );
          final lyricText = child.getElement('lyric')?.getElement('text');
          if (lyricText != null && lyricText.innerText.trim().isNotEmpty) {
            lyrics.add(
              LyricSyllable.exact(
                id: 'lyric-$id',
                measureIndex: measureIndex,
                position: position,
                text: lyricText.innerText,
                alignedNoteId: id,
              ),
            );
          }
        }
        if (!isChord) cursor = cursor + duration;
      }
      for (final direction in measureElement.findElements('direction')) {
        final words = direction
            .getElement('direction-type')
            ?.getElement('words')
            ?.innerText
            .trim();
        if (words != null && words.isNotEmpty) {
          sections.add(
            SongSection(
              id: 'section-${measureIndex + 1}-${sections.length}',
              name: words,
              measureIndex: measureIndex,
            ),
          );
        }
      }
      final barlines = measureElement.findElements('barline');
      for (final barline in barlines) {
        final repeat = barline.getElement('repeat');
        if (repeat?.getAttribute('direction') == 'forward') {
          pendingRepeatStart = measureIndex;
        } else if (repeat?.getAttribute('direction') == 'backward') {
          repeats.add(
            RepeatRegion(
              id: 'repeat-${repeats.length}',
              startMeasureIndex: pendingRepeatStart ?? 0,
              endMeasureIndex: measureIndex,
              times: int.tryParse(repeat?.getAttribute('times') ?? '') ?? 2,
            ),
          );
          pendingRepeatStart = null;
        }
      }
      final tempo = _readTempo(measureElement);
      measures.add(
        ChartMeasure.exact(
          number:
              int.tryParse(measureElement.getAttribute('number') ?? '') ??
              measureIndex + 1,
          length: time.quarterNoteLength,
          notes: List.unmodifiable(notes),
          rests: List.unmodifiable(rests),
          timeSignature: time,
          tempoBpm: tempo,
        ),
      );
    }
    if (measures.isEmpty) {
      throw const FormatException('The MusicXML part has no measures.');
    }
    final title = root
        .getElement('work')
        ?.getElement('work-title')
        ?.innerText
        .trim();
    final artist = root
        .getElement('identification')
        ?.findElements('creator')
        .where((element) => element.getAttribute('type') == 'composer')
        .firstOrNull
        ?.innerText
        .trim();
    return MusicXmlImportResult(
      chart: SongChart(
        id: 'musicxml-${DateTime.now().microsecondsSinceEpoch}',
        title: title?.isNotEmpty == true ? title! : 'Imported MusicXML',
        artist: artist ?? '',
        instrumentName:
            root
                .getElement('part-list')
                ?.getElement('score-part')
                ?.getElement('part-name')
                ?.innerText ??
            'Bass guitar',
        tuning: tuning,
        measures: List.unmodifiable(measures),
        lyrics: List.unmodifiable(lyrics),
        sections: List.unmodifiable(sections),
        repeats: List.unmodifiable(repeats),
      ),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  int _requiredDivisions(SongChart chart) {
    var result = 1;
    for (final measure in chart.measures) {
      for (final value in [
        measure.length,
        ...measure.notes.expand((note) => [note.position, note.duration]),
        ...measure.rests.expand((rest) => [rest.position, rest.duration]),
      ]) {
        result = _lcm(result, value.denominator);
      }
    }
    return result;
  }

  void _writeMeasureAttributes(
    XmlBuilder builder,
    SongChart chart,
    ChartMeasure measure,
    int divisions, {
    required bool includeTuning,
  }) {
    builder.element(
      'attributes',
      nest: () {
        builder
          ..element('divisions', nest: '$divisions')
          ..element(
            'time',
            nest: () {
              builder
                ..element('beats', nest: '${measure.timeSignature.numerator}')
                ..element(
                  'beat-type',
                  nest: '${measure.timeSignature.denominator}',
                );
            },
          );
        if (includeTuning) {
          builder.element(
            'staff-details',
            nest: () {
              builder.element(
                'staff-lines',
                nest: '${chart.tuning.strings.length}',
              );
              for (final (index, string) in chart.tuning.strings.indexed) {
                final pitch = _pitchParts(string.midiPitch);
                builder.element(
                  'staff-tuning',
                  attributes: {'line': '${index + 1}'},
                  nest: () {
                    builder.element('tuning-step', nest: pitch.$1);
                    if (pitch.$2 != 0) {
                      builder.element('tuning-alter', nest: '${pitch.$2}');
                    }
                    builder.element('tuning-octave', nest: '${pitch.$3}');
                  },
                );
              }
            },
          );
        }
      },
    );
  }

  void _writeDirections(XmlBuilder builder, SongChart chart, int measureIndex) {
    for (final section in chart.sections.where(
      (section) => section.measureIndex == measureIndex,
    )) {
      builder.element(
        'direction',
        nest: () => builder.element(
          'direction-type',
          nest: () => builder.element('words', nest: section.name),
        ),
      );
    }
  }

  void _writeEvents(
    XmlBuilder builder,
    SongChart chart,
    int measureIndex,
    int divisions,
  ) {
    final measure = chart.measures[measureIndex];
    final events = <({BeatFraction position, TabNote? note, RestEvent? rest})>[
      for (final note in measure.notes)
        (position: note.position, note: note, rest: null),
      for (final rest in measure.rests)
        (position: rest.position, note: null, rest: rest),
    ]..sort((a, b) => a.position.compareTo(b.position));
    for (final event in events) {
      final note = event.note;
      final rest = event.rest;
      final value = note?.value ?? rest!.value;
      final duration = note?.duration ?? rest!.duration;
      builder.element(
        'note',
        nest: () {
          if (rest != null) {
            builder.element('rest');
          } else {
            final pitch = _pitchParts(
              note!.midiPitch(chart.tuning, capo: chart.capo),
            );
            builder.element(
              'pitch',
              nest: () {
                builder.element('step', nest: pitch.$1);
                if (pitch.$2 != 0) {
                  builder.element('alter', nest: '${pitch.$2}');
                }
                builder.element('octave', nest: '${pitch.$3}');
              },
            );
          }
          builder
            ..element(
              'duration',
              nest: '${duration.numerator * divisions ~/ duration.denominator}',
            )
            ..element('voice', nest: '${note?.voice ?? rest!.voice}')
            ..element('type', nest: _musicXmlType(value));
          if (note != null) {
            builder.element(
              'notations',
              nest: () => builder.element(
                'technical',
                nest: () {
                  builder
                    ..element('string', nest: '${note.stringIndex + 1}')
                    ..element('fret', nest: '${note.fret}');
                  for (final technique in note.techniques) {
                    builder.element(_techniqueElement(technique.kind));
                  }
                },
              ),
            );
            for (final lyric in chart.lyrics.where(
              (lyric) =>
                  lyric.measureIndex == measureIndex &&
                  (lyric.alignedNoteId == note.id ||
                      (lyric.alignedNoteId == null &&
                          lyric.position == note.position)),
            )) {
              builder.element(
                'lyric',
                nest: () => builder.element('text', nest: lyric.text),
              );
            }
          }
        },
      );
    }
  }

  void _writeBarlines(XmlBuilder builder, SongChart chart, int measureIndex) {
    for (final repeat in chart.repeats) {
      if (repeat.startMeasureIndex == measureIndex) {
        builder.element(
          'barline',
          attributes: {'location': 'left'},
          nest: () =>
              builder.element('repeat', attributes: {'direction': 'forward'}),
        );
      }
      if (repeat.endMeasureIndex == measureIndex) {
        builder.element(
          'barline',
          attributes: {'location': 'right'},
          nest: () => builder.element(
            'repeat',
            attributes: {'direction': 'backward', 'times': '${repeat.times}'},
          ),
        );
      }
    }
  }

  BassTuning _readTuning(
    XmlElement attributes,
    List<MusicXmlDiagnostic> diagnostics,
  ) {
    final details = attributes.getElement('staff-details');
    final tunings = details?.findElements('staff-tuning').toList() ?? const [];
    if (tunings.isEmpty) {
      diagnostics.add(
        const MusicXmlDiagnostic(
          'No staff tuning was present; 4-string EADG was used.',
          isLoss: true,
        ),
      );
      return BassTuning.eadg;
    }
    return BassTuning(
      name: 'MusicXML tuning',
      strings: List.unmodifiable(
        tunings.map((element) {
          final step = element.getElement('tuning-step')!.innerText;
          final alter =
              int.tryParse(
                element.getElement('tuning-alter')?.innerText ?? '',
              ) ??
              0;
          final octave = int.parse(
            element.getElement('tuning-octave')!.innerText,
          );
          final midi = _midiPitch(step, alter, octave);
          return StringTuning(name: _pitchName(step, alter), midiPitch: midi);
        }),
      ),
    );
  }

  int _readMidiPitch(XmlElement? pitch) {
    if (pitch == null) {
      throw const FormatException('A pitched MusicXML note has no pitch.');
    }
    return _midiPitch(
      pitch.getElement('step')!.innerText,
      int.tryParse(pitch.getElement('alter')?.innerText ?? '') ?? 0,
      int.parse(pitch.getElement('octave')!.innerText),
    );
  }

  (int, int) _placeNote(
    BassTuning tuning,
    int pitch, {
    int? stringNumber,
    int? fret,
  }) {
    if (stringNumber != null &&
        fret != null &&
        stringNumber >= 1 &&
        stringNumber <= tuning.strings.length) {
      return (stringNumber - 1, fret);
    }
    final candidates = <(int, int)>[];
    for (final (index, string) in tuning.strings.indexed) {
      final candidateFret = pitch - string.midiPitch;
      if (candidateFret >= 0 && candidateFret <= 36) {
        candidates.add((index, candidateFret));
      }
    }
    if (candidates.isEmpty) {
      throw FormatException(
        'Pitch $pitch is not playable on the imported tuning.',
      );
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    return candidates.first;
  }

  List<TechniqueMark> _readTechniques(XmlElement note) {
    final technical = note.getElement('notations')?.getElement('technical');
    if (technical == null) return const [];
    final result = <TechniqueMark>[];
    for (final child in technical.children.whereType<XmlElement>()) {
      final kind = _techniqueKind(child.name.local);
      if (kind != null) result.add(TechniqueMark(kind));
    }
    return List.unmodifiable(result);
  }

  int? _readTempo(XmlElement measure) {
    for (final direction in measure.findElements('direction')) {
      final sound = direction.getElement('sound')?.getAttribute('tempo');
      final parsed = sound == null ? null : double.tryParse(sound)?.round();
      if (parsed != null) return parsed;
    }
    return null;
  }

  NoteValue _noteValueFor(
    BeatFraction duration,
    List<MusicXmlDiagnostic> diagnostics,
  ) {
    for (final value in NoteValue.values) {
      if (value.duration == duration) return value;
    }
    diagnostics.add(
      MusicXmlDiagnostic(
        'Duration $duration was approximated to the nearest supported value.',
        isLoss: true,
      ),
    );
    return NoteValue.values.reduce(
      (a, b) =>
          (a.duration.value - duration.value).abs() <=
              (b.duration.value - duration.value).abs()
          ? a
          : b,
    );
  }

  String _musicXmlType(NoteValue value) => switch (value) {
    NoteValue.whole => 'whole',
    NoteValue.half => 'half',
    NoteValue.quarter => 'quarter',
    NoteValue.eighth => 'eighth',
    NoteValue.sixteenth => '16th',
  };

  String _techniqueElement(TechniqueKind kind) => switch (kind) {
    TechniqueKind.slide => 'slide',
    TechniqueKind.bend => 'bend',
    TechniqueKind.hammerOn => 'hammer-on',
    TechniqueKind.pullOff => 'pull-off',
    TechniqueKind.naturalHarmonic => 'harmonic',
    TechniqueKind.artificialHarmonic => 'harmonic',
    TechniqueKind.deadNote => 'other-technical',
    TechniqueKind.palmMute => 'other-technical',
    TechniqueKind.letRing => 'other-technical',
    TechniqueKind.accent => 'other-technical',
  };

  TechniqueKind? _techniqueKind(String name) => switch (name) {
    'slide' => TechniqueKind.slide,
    'bend' => TechniqueKind.bend,
    'hammer-on' => TechniqueKind.hammerOn,
    'pull-off' => TechniqueKind.pullOff,
    'harmonic' => TechniqueKind.naturalHarmonic,
    _ => null,
  };

  (String, int, int) _pitchParts(int midi) {
    const steps = [
      ('C', 0),
      ('C', 1),
      ('D', 0),
      ('D', 1),
      ('E', 0),
      ('F', 0),
      ('F', 1),
      ('G', 0),
      ('G', 1),
      ('A', 0),
      ('A', 1),
      ('B', 0),
    ];
    final pitchClass = midi % 12;
    final octave = midi ~/ 12 - 1;
    return (steps[pitchClass].$1, steps[pitchClass].$2, octave);
  }

  int _midiPitch(String step, int alter, int octave) {
    const pitchClasses = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };
    final pitchClass = pitchClasses[step.toUpperCase()];
    if (pitchClass == null) {
      throw FormatException('Unsupported pitch step $step.');
    }
    return (octave + 1) * 12 + pitchClass + alter;
  }

  String _pitchName(String step, int alter) =>
      alter == 0 ? step : '$step${alter > 0 ? '#' : 'b'}';

  int _lcm(int a, int b) => a ~/ _gcd(a, b) * b;

  int _gcd(int a, int b) {
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a == 0 ? 1 : a;
  }
}
