import 'dart:convert';

class BeatFraction implements Comparable<BeatFraction> {
  const BeatFraction._(this.numerator, this.denominator);

  factory BeatFraction(int numerator, [int denominator = 1]) {
    if (denominator == 0) {
      throw const FormatException('A beat denominator cannot be zero.');
    }
    final sign = denominator < 0 ? -1 : 1;
    final divisor = _gcd(numerator.abs(), denominator.abs());
    return BeatFraction._(
      sign * numerator ~/ divisor,
      denominator.abs() ~/ divisor,
    );
  }

  factory BeatFraction.fromNum(num value) {
    if (!value.isFinite) {
      throw const FormatException('A beat position must be finite.');
    }
    if (value is int) return BeatFraction(value);
    final text = value.toString();
    if (text.contains('e') || text.contains('E')) {
      const scale = 1000000;
      return BeatFraction((value * scale).round(), scale);
    }
    final parts = text.split('.');
    if (parts.length == 1) return BeatFraction(int.parse(parts.single));
    final scale = _pow10(parts[1].length);
    return BeatFraction(
      int.parse(parts[0]) * scale +
          (value.isNegative ? -1 : 1) * int.parse(parts[1]),
      scale,
    );
  }

  static const zero = BeatFraction._(0, 1);
  static const one = BeatFraction._(1, 1);

  final int numerator;
  final int denominator;

  double get value => numerator / denominator;
  bool get isNegative => numerator < 0;
  bool get isPositive => numerator > 0;

  BeatFraction operator +(BeatFraction other) => BeatFraction(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  BeatFraction operator -(BeatFraction other) => BeatFraction(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );

  BeatFraction operator *(BeatFraction other) => BeatFraction(
    numerator * other.numerator,
    denominator * other.denominator,
  );

  Map<String, Object> toJson() => {
    'numerator': numerator,
    'denominator': denominator,
  };

  factory BeatFraction.fromJson(Map<String, Object?> json) =>
      BeatFraction(json['numerator']! as int, json['denominator']! as int);

  @override
  int compareTo(BeatFraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is BeatFraction &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() =>
      denominator == 1 ? '$numerator' : '$numerator/$denominator';

  static int _gcd(int a, int b) {
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a == 0 ? 1 : a;
  }

  static int _pow10(int exponent) {
    var value = 1;
    for (var index = 0; index < exponent; index += 1) {
      value *= 10;
    }
    return value;
  }
}

enum NoteValue {
  whole('Semibreve', 4, 1),
  half('Minim', 2, 1),
  quarter('Crotchet', 1, 1),
  eighth('Quaver', 1, 2),
  sixteenth('Semiquaver', 1, 4);

  const NoteValue(this.label, this.durationNumerator, this.durationDenominator);

  final String label;
  final int durationNumerator;
  final int durationDenominator;
  double get quarterNotes => duration.value;
  BeatFraction get duration =>
      BeatFraction(durationNumerator, durationDenominator);

  Map<String, Object> toJson() => {'name': name};
}

class StringTuning {
  const StringTuning({required this.name, required this.midiPitch});

  final String name;
  final int midiPitch;

  Map<String, Object> toJson() => {'name': name, 'midiPitch': midiPitch};

  factory StringTuning.fromJson(Map<String, Object?> json) => StringTuning(
    name: json['name']! as String,
    midiPitch: json['midiPitch']! as int,
  );
}

class BassTuning {
  const BassTuning({required this.name, required this.strings});

  final String name;

  /// Display order is highest string to lowest string, matching tablature.
  final List<StringTuning> strings;

  static const beadg = BassTuning(
    name: '5-string BEADG',
    strings: [
      StringTuning(name: 'G', midiPitch: 43),
      StringTuning(name: 'D', midiPitch: 38),
      StringTuning(name: 'A', midiPitch: 33),
      StringTuning(name: 'E', midiPitch: 28),
      StringTuning(name: 'B', midiPitch: 23),
    ],
  );

  static const eadg = BassTuning(
    name: '4-string EADG',
    strings: [
      StringTuning(name: 'G', midiPitch: 43),
      StringTuning(name: 'D', midiPitch: 38),
      StringTuning(name: 'A', midiPitch: 33),
      StringTuning(name: 'E', midiPitch: 28),
    ],
  );

  Map<String, Object> toJson() => {
    'name': name,
    'strings': [for (final string in strings) string.toJson()],
  };

  factory BassTuning.fromJson(Map<String, Object?> json) => BassTuning(
    name: json['name']! as String,
    strings: List.unmodifiable(
      (json['strings']! as List).map(
        (value) =>
            StringTuning.fromJson((value as Map).cast<String, Object?>()),
      ),
    ),
  );
}

class TabNote {
  TabNote({
    required this.id,
    required num beat,
    required this.stringIndex,
    required this.fret,
    required this.value,
    this.voice = 1,
    this.dots = 0,
    this.tieStart = false,
    this.tieEnd = false,
    this.tuplet,
  }) : position = BeatFraction.fromNum(beat);

  const TabNote.exact({
    required this.id,
    required this.position,
    required this.stringIndex,
    required this.fret,
    required this.value,
    this.voice = 1,
    this.dots = 0,
    this.tieStart = false,
    this.tieEnd = false,
    this.tuplet,
  });

  final String id;
  final BeatFraction position;
  final int stringIndex;
  final int fret;
  final NoteValue value;
  final int voice;
  final int dots;
  final bool tieStart;
  final bool tieEnd;
  final TupletRatio? tuplet;

  double get beat => position.value;

  BeatFraction get duration {
    var result = value.duration;
    var addition = result;
    for (var index = 0; index < dots; index += 1) {
      addition = addition * BeatFraction(1, 2);
      result = result + addition;
    }
    final ratio = tuplet;
    return ratio == null ? result : result * ratio.durationScale;
  }

  int midiPitch(BassTuning tuning) =>
      tuning.strings[stringIndex].midiPitch + fret;

  TabNote copyWith({
    num? beat,
    BeatFraction? position,
    int? stringIndex,
    int? fret,
    NoteValue? value,
    int? voice,
    int? dots,
    bool? tieStart,
    bool? tieEnd,
    TupletRatio? tuplet,
    bool clearTuplet = false,
  }) {
    return TabNote.exact(
      id: id,
      position:
          position ??
          (beat == null ? this.position : BeatFraction.fromNum(beat)),
      stringIndex: stringIndex ?? this.stringIndex,
      fret: fret ?? this.fret,
      value: value ?? this.value,
      voice: voice ?? this.voice,
      dots: dots ?? this.dots,
      tieStart: tieStart ?? this.tieStart,
      tieEnd: tieEnd ?? this.tieEnd,
      tuplet: clearTuplet ? null : tuplet ?? this.tuplet,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'position': position.toJson(),
    'stringIndex': stringIndex,
    'fret': fret,
    'value': value.name,
    'voice': voice,
    'dots': dots,
    'tieStart': tieStart,
    'tieEnd': tieEnd,
    if (tuplet != null) 'tuplet': tuplet!.toJson(),
  };

  factory TabNote.fromJson(Map<String, Object?> json, {int schemaVersion = 2}) {
    final position = schemaVersion == 1
        ? BeatFraction.fromNum(json['beat']! as num)
        : BeatFraction.fromJson(
            (json['position']! as Map).cast<String, Object?>(),
          );
    final tupletJson = json['tuplet'];
    return TabNote.exact(
      id: json['id']! as String,
      position: position,
      stringIndex: json['stringIndex']! as int,
      fret: json['fret']! as int,
      value: NoteValue.values.byName(json['value']! as String),
      voice: json['voice'] as int? ?? 1,
      dots: json['dots'] as int? ?? 0,
      tieStart: json['tieStart'] as bool? ?? false,
      tieEnd: json['tieEnd'] as bool? ?? false,
      tuplet: tupletJson == null
          ? null
          : TupletRatio.fromJson((tupletJson as Map).cast<String, Object?>()),
    );
  }
}

class TupletRatio {
  const TupletRatio({required this.actual, required this.normal});

  final int actual;
  final int normal;

  BeatFraction get durationScale => BeatFraction(normal, actual);

  Map<String, Object> toJson() => {'actual': actual, 'normal': normal};

  factory TupletRatio.fromJson(Map<String, Object?> json) => TupletRatio(
    actual: json['actual']! as int,
    normal: json['normal']! as int,
  );
}

class RestEvent {
  const RestEvent({
    required this.id,
    required this.position,
    required this.value,
    this.voice = 1,
    this.dots = 0,
    this.tuplet,
  });

  final String id;
  final BeatFraction position;
  final NoteValue value;
  final int voice;
  final int dots;
  final TupletRatio? tuplet;

  BeatFraction get duration => TabNote.exact(
    id: id,
    position: position,
    stringIndex: 0,
    fret: 0,
    value: value,
    voice: voice,
    dots: dots,
    tuplet: tuplet,
  ).duration;

  Map<String, Object> toJson() => {
    'id': id,
    'position': position.toJson(),
    'value': value.name,
    'voice': voice,
    'dots': dots,
    if (tuplet != null) 'tuplet': tuplet!.toJson(),
  };

  factory RestEvent.fromJson(Map<String, Object?> json) {
    final tupletJson = json['tuplet'];
    return RestEvent(
      id: json['id']! as String,
      position: BeatFraction.fromJson(
        (json['position']! as Map).cast<String, Object?>(),
      ),
      value: NoteValue.values.byName(json['value']! as String),
      voice: json['voice'] as int? ?? 1,
      dots: json['dots'] as int? ?? 0,
      tuplet: tupletJson == null
          ? null
          : TupletRatio.fromJson((tupletJson as Map).cast<String, Object?>()),
    );
  }
}

class ChartMeasure {
  ChartMeasure({
    required this.number,
    required this.notes,
    num beats = 4,
    this.rests = const [],
    this.timeSignature = const TimeSignature(4, 4),
    this.keySignature = 'C',
    this.tempoBpm,
  }) : length = BeatFraction.fromNum(beats);

  const ChartMeasure.exact({
    required this.number,
    required this.notes,
    required this.length,
    this.rests = const [],
    this.timeSignature = const TimeSignature(4, 4),
    this.keySignature = 'C',
    this.tempoBpm,
  });

  final int number;
  final BeatFraction length;
  final List<TabNote> notes;
  final List<RestEvent> rests;
  final TimeSignature timeSignature;
  final String keySignature;
  final int? tempoBpm;

  double get beats => length.value;

  ChartMeasure replaceNote(TabNote replacement) {
    return ChartMeasure.exact(
      number: number,
      length: length,
      notes: [
        for (final note in notes)
          if (note.id == replacement.id) replacement else note,
      ],
      rests: rests,
      timeSignature: timeSignature,
      keySignature: keySignature,
      tempoBpm: tempoBpm,
    );
  }

  Map<String, Object> toJson() {
    final result = <String, Object>{
      'number': number,
      'length': length.toJson(),
      'notes': [for (final note in notes) note.toJson()],
      'rests': [for (final rest in rests) rest.toJson()],
      'timeSignature': timeSignature.toJson(),
      'keySignature': keySignature,
    };
    if (tempoBpm case final tempo?) result['tempoBpm'] = tempo;
    return result;
  }

  factory ChartMeasure.fromJson(
    Map<String, Object?> json, {
    int schemaVersion = 2,
  }) => ChartMeasure.exact(
    number: json['number']! as int,
    length: schemaVersion == 1
        ? BeatFraction.fromNum(json['beats']! as num)
        : BeatFraction.fromJson(
            (json['length']! as Map).cast<String, Object?>(),
          ),
    notes: List.unmodifiable(
      (json['notes']! as List).map(
        (value) => TabNote.fromJson(
          (value as Map).cast<String, Object?>(),
          schemaVersion: schemaVersion,
        ),
      ),
    ),
    rests: schemaVersion == 1
        ? const []
        : List.unmodifiable(
            ((json['rests'] as List?) ?? const []).map(
              (value) =>
                  RestEvent.fromJson((value as Map).cast<String, Object?>()),
            ),
          ),
    timeSignature: schemaVersion == 1
        ? const TimeSignature(4, 4)
        : TimeSignature.fromJson(
            (json['timeSignature']! as Map).cast<String, Object?>(),
          ),
    keySignature: json['keySignature'] as String? ?? 'C',
    tempoBpm: json['tempoBpm'] as int?,
  );

  List<String> validationErrors() {
    final errors = <String>[];
    if (!length.isPositive) errors.add('Measure $number has no duration.');
    if (!timeSignature.isValid) {
      errors.add('Measure $number has an invalid time signature.');
    } else if (length != timeSignature.quarterNoteLength) {
      errors.add('Measure $number duration does not match its time signature.');
    }
    for (final note in notes) {
      if (note.voice < 1 ||
          note.dots < 0 ||
          note.dots > 3 ||
          (note.tuplet != null &&
              (note.tuplet!.actual < 1 || note.tuplet!.normal < 1))) {
        errors.add('Note ${note.id} has invalid rhythm metadata.');
      }
    }
    for (final rest in rests) {
      if (rest.voice < 1 ||
          rest.dots < 0 ||
          rest.dots > 3 ||
          (rest.tuplet != null &&
              (rest.tuplet!.actual < 1 || rest.tuplet!.normal < 1))) {
        errors.add('Rest ${rest.id} has invalid rhythm metadata.');
      }
    }
    for (final voice in {
      for (final note in notes) note.voice,
      for (final rest in rests) rest.voice,
    }) {
      var end = BeatFraction.zero;
      final events = <({BeatFraction position, BeatFraction duration})>[
        for (final note in notes.where((note) => note.voice == voice))
          (position: note.position, duration: note.duration),
        for (final rest in rests.where((rest) => rest.voice == voice))
          (position: rest.position, duration: rest.duration),
      ]..sort((a, b) => a.position.compareTo(b.position));
      for (final event in events) {
        if (event.position.isNegative) {
          errors.add('Measure $number voice $voice starts before beat zero.');
        }
        if (event.position.compareTo(end) < 0) {
          errors.add(
            'Measure $number voice $voice contains overlapping events.',
          );
        }
        end = event.position + event.duration;
      }
      if (end.compareTo(length) > 0) {
        errors.add(
          'Measure $number voice $voice exceeds the measure duration.',
        );
      }
    }
    return errors;
  }
}

class TimeSignature {
  const TimeSignature(this.numerator, this.denominator);

  final int numerator;
  final int denominator;

  bool get isValid =>
      numerator > 0 &&
      denominator > 0 &&
      (denominator & (denominator - 1)) == 0;

  BeatFraction get quarterNoteLength =>
      BeatFraction(numerator * 4, denominator);

  Map<String, Object> toJson() => {
    'numerator': numerator,
    'denominator': denominator,
  };

  factory TimeSignature.fromJson(Map<String, Object?> json) =>
      TimeSignature(json['numerator']! as int, json['denominator']! as int);
}

class LyricSyllable {
  LyricSyllable({
    required this.id,
    required this.measureIndex,
    required num beat,
    required this.text,
    this.isBackingVocal = false,
  }) : position = BeatFraction.fromNum(beat);

  const LyricSyllable.exact({
    required this.id,
    required this.measureIndex,
    required this.position,
    required this.text,
    this.isBackingVocal = false,
  });

  final String id;
  final int measureIndex;
  final BeatFraction position;
  final String text;
  final bool isBackingVocal;

  double get beat => position.value;

  LyricSyllable copyWith({
    int? measureIndex,
    num? beat,
    BeatFraction? position,
    String? text,
    bool? isBackingVocal,
  }) {
    return LyricSyllable.exact(
      id: id,
      measureIndex: measureIndex ?? this.measureIndex,
      position:
          position ??
          (beat == null ? this.position : BeatFraction.fromNum(beat)),
      text: text ?? this.text,
      isBackingVocal: isBackingVocal ?? this.isBackingVocal,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'measureIndex': measureIndex,
    'position': position.toJson(),
    'text': text,
    'isBackingVocal': isBackingVocal,
  };

  factory LyricSyllable.fromJson(
    Map<String, Object?> json, {
    int schemaVersion = 2,
  }) => LyricSyllable.exact(
    id: json['id']! as String,
    measureIndex: json['measureIndex']! as int,
    position: schemaVersion == 1
        ? BeatFraction.fromNum(json['beat']! as num)
        : BeatFraction.fromJson(
            (json['position']! as Map).cast<String, Object?>(),
          ),
    text: json['text']! as String,
    isBackingVocal: json['isBackingVocal'] as bool? ?? false,
  );
}

class SongSection {
  const SongSection({
    required this.id,
    required this.name,
    required this.measureIndex,
  });

  final String id;
  final String name;
  final int measureIndex;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'measureIndex': measureIndex,
  };

  factory SongSection.fromJson(Map<String, Object?> json) => SongSection(
    id: json['id']! as String,
    name: json['name']! as String,
    measureIndex: json['measureIndex']! as int,
  );
}

class RepeatEnding {
  const RepeatEnding({
    required this.numbers,
    required this.startMeasureIndex,
    required this.endMeasureIndex,
  });

  final List<int> numbers;
  final int startMeasureIndex;
  final int endMeasureIndex;

  Map<String, Object> toJson() => {
    'numbers': numbers,
    'startMeasureIndex': startMeasureIndex,
    'endMeasureIndex': endMeasureIndex,
  };

  factory RepeatEnding.fromJson(Map<String, Object?> json) => RepeatEnding(
    numbers: List.unmodifiable((json['numbers']! as List).cast<int>()),
    startMeasureIndex: json['startMeasureIndex']! as int,
    endMeasureIndex: json['endMeasureIndex']! as int,
  );
}

class RepeatRegion {
  const RepeatRegion({
    required this.id,
    required this.startMeasureIndex,
    required this.endMeasureIndex,
    this.times = 2,
    this.endings = const [],
  });

  final String id;
  final int startMeasureIndex;
  final int endMeasureIndex;
  final int times;
  final List<RepeatEnding> endings;

  Map<String, Object> toJson() => {
    'id': id,
    'startMeasureIndex': startMeasureIndex,
    'endMeasureIndex': endMeasureIndex,
    'times': times,
    'endings': [for (final ending in endings) ending.toJson()],
  };

  factory RepeatRegion.fromJson(Map<String, Object?> json) => RepeatRegion(
    id: json['id']! as String,
    startMeasureIndex: json['startMeasureIndex']! as int,
    endMeasureIndex: json['endMeasureIndex']! as int,
    times: json['times'] as int? ?? 2,
    endings: List.unmodifiable(
      ((json['endings'] as List?) ?? const []).map(
        (value) =>
            RepeatEnding.fromJson((value as Map).cast<String, Object?>()),
      ),
    ),
  );
}

class SongChart {
  const SongChart({
    this.id = 'semantic-foundation',
    required this.title,
    required this.artist,
    required this.tuning,
    required this.measures,
    required this.lyrics,
    this.sections = const [],
    this.repeats = const [],
  });

  static const schemaVersion = 2;

  final String id;
  final String title;
  final String artist;
  final BassTuning tuning;
  final List<ChartMeasure> measures;
  final List<LyricSyllable> lyrics;
  final List<SongSection> sections;
  final List<RepeatRegion> repeats;

  TabNote? noteById(String id) {
    for (final measure in measures) {
      for (final note in measure.notes) {
        if (note.id == id) return note;
      }
    }
    return null;
  }

  SongChart replaceNote(TabNote replacement) {
    return SongChart(
      id: id,
      title: title,
      artist: artist,
      tuning: tuning,
      measures: [
        for (final measure in measures) measure.replaceNote(replacement),
      ],
      lyrics: lyrics,
      sections: sections,
      repeats: repeats,
    );
  }

  SongChart replaceLyric(LyricSyllable replacement) {
    return SongChart(
      id: id,
      title: title,
      artist: artist,
      tuning: tuning,
      measures: measures,
      lyrics: [
        for (final lyric in lyrics)
          if (lyric.id == replacement.id) replacement else lyric,
      ],
      sections: sections,
      repeats: repeats,
    );
  }

  SongChart copyWith({
    String? id,
    String? title,
    String? artist,
    BassTuning? tuning,
    List<ChartMeasure>? measures,
    List<LyricSyllable>? lyrics,
    List<SongSection>? sections,
    List<RepeatRegion>? repeats,
  }) {
    return SongChart(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      tuning: tuning ?? this.tuning,
      measures: measures ?? this.measures,
      lyrics: lyrics ?? this.lyrics,
      sections: sections ?? this.sections,
      repeats: repeats ?? this.repeats,
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'title': title,
    'artist': artist,
    'tuning': tuning.toJson(),
    'measures': [for (final measure in measures) measure.toJson()],
    'lyrics': [for (final lyric in lyrics) lyric.toJson()],
    'sections': [for (final section in sections) section.toJson()],
    'repeats': [for (final repeat in repeats) repeat.toJson()],
  };

  String encode() => jsonEncode(toJson());

  factory SongChart.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version < 1 || version > schemaVersion) {
      throw FormatException('Unsupported semantic chart schema $version.');
    }
    return SongChart(
      id: json['id']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      tuning: BassTuning.fromJson(
        (json['tuning']! as Map).cast<String, Object?>(),
      ),
      measures: List.unmodifiable(
        (json['measures']! as List).map(
          (value) => ChartMeasure.fromJson(
            (value as Map).cast<String, Object?>(),
            schemaVersion: version,
          ),
        ),
      ),
      lyrics: List.unmodifiable(
        (json['lyrics']! as List).map(
          (value) => LyricSyllable.fromJson(
            (value as Map).cast<String, Object?>(),
            schemaVersion: version,
          ),
        ),
      ),
      sections: version == 1
          ? const []
          : List.unmodifiable(
              ((json['sections'] as List?) ?? const []).map(
                (value) => SongSection.fromJson(
                  (value as Map).cast<String, Object?>(),
                ),
              ),
            ),
      repeats: version == 1
          ? const []
          : List.unmodifiable(
              ((json['repeats'] as List?) ?? const []).map(
                (value) => RepeatRegion.fromJson(
                  (value as Map).cast<String, Object?>(),
                ),
              ),
            ),
    );
  }

  List<String> validationErrors() {
    final errors = <String>[
      for (final measure in measures) ...measure.validationErrors(),
    ];
    for (final section in sections) {
      if (section.measureIndex < 0 || section.measureIndex >= measures.length) {
        errors.add('Section ${section.name} points outside the song.');
      }
    }
    for (final repeat in repeats) {
      if (repeat.startMeasureIndex < 0 ||
          repeat.endMeasureIndex < repeat.startMeasureIndex ||
          repeat.endMeasureIndex >= measures.length ||
          repeat.times < 2) {
        errors.add('Repeat ${repeat.id} has invalid boundaries.');
        continue;
      }
      for (final ending in repeat.endings) {
        if (ending.numbers.isEmpty ||
            ending.numbers.any(
              (number) => number < 1 || number > repeat.times,
            ) ||
            ending.startMeasureIndex < repeat.startMeasureIndex ||
            ending.endMeasureIndex < ending.startMeasureIndex ||
            ending.endMeasureIndex > repeat.endMeasureIndex) {
          errors.add('Repeat ${repeat.id} has an invalid ending.');
        }
      }
    }
    for (final lyric in lyrics) {
      if (lyric.measureIndex < 0 || lyric.measureIndex >= measures.length) {
        errors.add('Lyric ${lyric.id} points outside the song.');
      }
    }
    return errors;
  }

  factory SongChart.decode(String source) =>
      SongChart.fromJson((jsonDecode(source) as Map).cast<String, Object?>());

  static SongChart foundationExample() {
    return SongChart(
      id: 'semantic-foundation',
      title: 'Foundation Groove',
      artist: 'Music Tabbler',
      tuning: BassTuning.beadg,
      measures: [
        ChartMeasure(
          number: 1,
          notes: [
            TabNote(
              id: 'n1',
              beat: 0,
              stringIndex: 3,
              fret: 3,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n2',
              beat: 1,
              stringIndex: 3,
              fret: 3,
              value: NoteValue.eighth,
            ),
            TabNote(
              id: 'n3',
              beat: 2,
              stringIndex: 2,
              fret: 1,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n4',
              beat: 3,
              stringIndex: 2,
              fret: 3,
              value: NoteValue.eighth,
            ),
          ],
        ),
        ChartMeasure(
          number: 2,
          notes: [
            TabNote(
              id: 'n5',
              beat: 0,
              stringIndex: 1,
              fret: 3,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n6',
              beat: 1,
              stringIndex: 2,
              fret: 5,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n7',
              beat: 2,
              stringIndex: 3,
              fret: 5,
              value: NoteValue.eighth,
            ),
            TabNote(
              id: 'n8',
              beat: 3,
              stringIndex: 4,
              fret: 5,
              value: NoteValue.quarter,
            ),
          ],
        ),
      ],
      lyrics: [
        LyricSyllable(id: 'l1', measureIndex: 0, beat: 0, text: 'main'),
        LyricSyllable(id: 'l2', measureIndex: 0, beat: 2, text: 'vo-cal'),
        LyricSyllable(
          id: 'l3',
          measureIndex: 1,
          beat: 0,
          text: 'BACK',
          isBackingVocal: true,
        ),
        LyricSyllable(
          id: 'l4',
          measureIndex: 1,
          beat: 2,
          text: 'ING',
          isBackingVocal: true,
        ),
      ],
    );
  }
}
