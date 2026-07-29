import 'visual_chart_models.dart';

enum VisualTabSourceType { positionedPdf, rasterOcr }

enum VisualTabTokenKind { fret, deadNote, measureNumber, ambiguous }

enum VisualConnectedComponentSide { unresolved, upper, lower }

class VisualConnectedNotationRisk {
  const VisualConnectedNotationRisk({
    required this.id,
    required this.rect,
    required this.gapIndex,
    this.side = VisualConnectedComponentSide.unresolved,
  });

  final String id;
  final NormalizedRect rect;
  final int gapIndex;
  final VisualConnectedComponentSide side;

  VisualConnectedNotationRisk copyWith({VisualConnectedComponentSide? side}) {
    return VisualConnectedNotationRisk(
      id: id,
      rect: rect,
      gapIndex: gapIndex,
      side: side ?? this.side,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'rect': rect.toJson(),
    'gapIndex': gapIndex,
    'side': side.name,
  };

  factory VisualConnectedNotationRisk.fromJson(Map<String, Object?> json) {
    return VisualConnectedNotationRisk(
      id: json['id'] as String? ?? 'legacy_risk',
      rect: NormalizedRect.fromJson(
        ((json['rect'] as Map?) ?? json).cast<String, Object?>(),
      ),
      gapIndex: json['gapIndex'] as int? ?? 0,
      side: VisualConnectedComponentSide.values.byName(
        json['side'] as String? ?? VisualConnectedComponentSide.unresolved.name,
      ),
    );
  }
}

class VisualTabToken {
  const VisualTabToken({
    required this.id,
    required this.text,
    required this.rect,
    required this.kind,
    this.stringIndex,
    this.confidence = 1,
    this.enabled = true,
  });

  final String id;
  final String text;
  final NormalizedRect rect;
  final VisualTabTokenKind kind;
  final int? stringIndex;
  final double confidence;
  final bool enabled;

  bool get isFretLike =>
      kind == VisualTabTokenKind.fret || kind == VisualTabTokenKind.deadNote;

  VisualTabToken copyWith({
    String? text,
    NormalizedRect? rect,
    VisualTabTokenKind? kind,
    int? stringIndex,
    bool clearStringIndex = false,
    double? confidence,
    bool? enabled,
  }) {
    return VisualTabToken(
      id: id,
      text: text ?? this.text,
      rect: rect ?? this.rect,
      kind: kind ?? this.kind,
      stringIndex: clearStringIndex ? null : stringIndex ?? this.stringIndex,
      confidence: confidence ?? this.confidence,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'rect': rect.toJson(),
    'kind': kind.name,
    'stringIndex': stringIndex,
    'confidence': confidence,
    'enabled': enabled,
  };

  factory VisualTabToken.fromJson(Map<String, Object?> json) {
    return VisualTabToken(
      id: json['id']! as String,
      text: json['text']! as String,
      rect: NormalizedRect.fromJson(
        (json['rect']! as Map).cast<String, Object?>(),
      ),
      kind: VisualTabTokenKind.values.byName(json['kind']! as String),
      stringIndex: json['stringIndex'] as int?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class VisualTabSystem {
  const VisualTabSystem({
    required this.id,
    required this.rect,
    required this.stringLines,
    this.barLines = const [],
    this.tokens = const [],
    this.connectedNotationRisks = const [],
    this.confidence = 1,
  });

  final String id;
  final NormalizedRect rect;
  final List<double> stringLines;
  final List<double> barLines;
  final List<VisualTabToken> tokens;
  final List<VisualConnectedNotationRisk> connectedNotationRisks;
  final double confidence;

  VisualTabSystem copyWith({
    NormalizedRect? rect,
    List<double>? stringLines,
    List<double>? barLines,
    List<VisualTabToken>? tokens,
    List<VisualConnectedNotationRisk>? connectedNotationRisks,
    double? confidence,
  }) {
    return VisualTabSystem(
      id: id,
      rect: rect ?? this.rect,
      stringLines: stringLines ?? this.stringLines,
      barLines: barLines ?? this.barLines,
      tokens: tokens ?? this.tokens,
      connectedNotationRisks:
          connectedNotationRisks ?? this.connectedNotationRisks,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'rect': rect.toJson(),
    'stringLines': stringLines,
    'barLines': barLines,
    'tokens': tokens.map((token) => token.toJson()).toList(),
    'connectedNotationRisks': connectedNotationRisks
        .map((risk) => risk.toJson())
        .toList(),
    'confidence': confidence,
  };

  factory VisualTabSystem.fromJson(Map<String, Object?> json) {
    return VisualTabSystem(
      id: json['id']! as String,
      rect: NormalizedRect.fromJson(
        (json['rect']! as Map).cast<String, Object?>(),
      ),
      stringLines: (json['stringLines']! as List)
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      barLines: ((json['barLines'] as List?) ?? const [])
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      tokens: ((json['tokens'] as List?) ?? const [])
          .map(
            (value) =>
                VisualTabToken.fromJson((value as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      connectedNotationRisks:
          ((json['connectedNotationRisks'] as List?) ?? const [])
              .map(
                (value) => VisualConnectedNotationRisk.fromJson(
                  (value as Map).cast<String, Object?>(),
                ),
              )
              .toList(growable: false),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
    );
  }
}

class VisualTabAnalysis {
  const VisualTabAnalysis({
    required this.stripId,
    required this.sourceType,
    this.systems = const [],
    this.warnings = const [],
  });

  final String stripId;
  final VisualTabSourceType sourceType;
  final List<VisualTabSystem> systems;
  final List<String> warnings;

  int get enabledFretTokenCount => systems.fold(
    0,
    (total, system) =>
        total +
        system.tokens
            .where((token) => token.enabled && token.isFretLike)
            .length,
  );

  VisualTabAnalysis copyWith({
    VisualTabSourceType? sourceType,
    List<VisualTabSystem>? systems,
    List<String>? warnings,
  }) {
    return VisualTabAnalysis(
      stripId: stripId,
      sourceType: sourceType ?? this.sourceType,
      systems: systems ?? this.systems,
      warnings: warnings ?? this.warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'stripId': stripId,
    'sourceType': sourceType.name,
    'systems': systems.map((system) => system.toJson()).toList(),
    'warnings': warnings,
  };

  factory VisualTabAnalysis.fromJson(Map<String, Object?> json) {
    return VisualTabAnalysis(
      stripId: json['stripId']! as String,
      sourceType: VisualTabSourceType.values.byName(
        json['sourceType']! as String,
      ),
      systems: ((json['systems'] as List?) ?? const [])
          .map(
            (value) => VisualTabSystem.fromJson(
              (value as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      warnings: ((json['warnings'] as List?) ?? const []).cast<String>().toList(
        growable: false,
      ),
    );
  }
}

class VisualStringRoute {
  const VisualStringRoute({
    required this.sourceString,
    required this.targetString,
    required this.fretOffset,
    this.manualOffset,
  });

  final int sourceString;
  final int targetString;
  final int fretOffset;
  final int? manualOffset;

  int get effectiveOffset => manualOffset ?? fretOffset;
  bool get hasManualOverride => manualOffset != null;

  Map<String, Object?> toJson() => {
    'sourceString': sourceString,
    'targetString': targetString,
    'fretOffset': fretOffset,
    'manualOffset': manualOffset,
  };

  factory VisualStringRoute.fromJson(Map<String, Object?> json) {
    return VisualStringRoute(
      sourceString: json['sourceString']! as int,
      targetString: json['targetString']! as int,
      fretOffset: json['fretOffset']! as int,
      manualOffset: json['manualOffset'] as int?,
    );
  }
}

class VisualTabTransformConfiguration {
  VisualTabTransformConfiguration({
    required this.sourceLabels,
    required this.sourceOpenMidis,
    required this.sourceCapo,
    required this.targetLabels,
    required this.targetOpenMidis,
    required this.targetCapo,
    required this.globalPitchChange,
    required this.routes,
    this.selectedStringPitchChanges = const {},
    this.compactTabOnly = true,
  }) {
    if (sourceLabels.length != sourceOpenMidis.length ||
        targetLabels.length != targetOpenMidis.length) {
      throw const FormatException(
        'Every source and target string needs a label and pitch.',
      );
    }
    if (sourceCapo < 0 ||
        sourceCapo > 24 ||
        targetCapo < 0 ||
        targetCapo > 24) {
      throw const FormatException('Capo must be between 0 and 24.');
    }
    validateMonotonicVisualRoutes(
      routes,
      sourceStringCount: sourceLabels.length,
      targetStringCount: targetLabels.length,
    );
  }

  final List<String> sourceLabels;
  final List<int> sourceOpenMidis;
  final int sourceCapo;
  final List<String> targetLabels;
  final List<int> targetOpenMidis;
  final int targetCapo;
  final int globalPitchChange;
  final Map<int, int> selectedStringPitchChanges;
  final List<VisualStringRoute> routes;
  final bool compactTabOnly;

  int pitchChangeForSourceString(int sourceString) =>
      selectedStringPitchChanges[sourceString] ?? globalPitchChange;

  int? get unusedTargetString {
    if (targetLabels.length == sourceLabels.length) return null;
    final used = routes.map((route) => route.targetString).toSet();
    for (var index = 0; index < targetLabels.length; index += 1) {
      if (!used.contains(index)) return index;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'sourceLabels': sourceLabels,
    'sourceOpenMidis': sourceOpenMidis,
    'sourceCapo': sourceCapo,
    'targetLabels': targetLabels,
    'targetOpenMidis': targetOpenMidis,
    'targetCapo': targetCapo,
    'globalPitchChange': globalPitchChange,
    'selectedStringPitchChanges': {
      for (final entry in selectedStringPitchChanges.entries)
        entry.key.toString(): entry.value,
    },
    'routes': routes.map((route) => route.toJson()).toList(),
    'compactTabOnly': compactTabOnly,
  };

  factory VisualTabTransformConfiguration.fromJson(Map<String, Object?> json) {
    return VisualTabTransformConfiguration(
      sourceLabels: (json['sourceLabels']! as List).cast<String>(),
      sourceOpenMidis: (json['sourceOpenMidis']! as List).cast<int>(),
      sourceCapo: json['sourceCapo']! as int,
      targetLabels: (json['targetLabels']! as List).cast<String>(),
      targetOpenMidis: (json['targetOpenMidis']! as List).cast<int>(),
      targetCapo: json['targetCapo']! as int,
      globalPitchChange: json['globalPitchChange']! as int,
      selectedStringPitchChanges:
          ((json['selectedStringPitchChanges'] as Map?) ?? const {}).map(
            (key, value) => MapEntry(int.parse(key as String), value as int),
          ),
      routes: (json['routes']! as List)
          .map(
            (value) => VisualStringRoute.fromJson(
              (value as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      compactTabOnly: json['compactTabOnly'] as bool? ?? true,
    );
  }
}

int calculateVisualRouteFretOffset({
  required int sourceOpenMidi,
  required int sourceCapo,
  required int desiredPitchChange,
  required int targetOpenMidi,
  required int targetCapo,
}) {
  return sourceOpenMidi +
      sourceCapo +
      desiredPitchChange -
      targetOpenMidi -
      targetCapo;
}

void validateMonotonicVisualRoutes(
  List<VisualStringRoute> routes, {
  required int sourceStringCount,
  required int targetStringCount,
}) {
  if (targetStringCount != sourceStringCount &&
      targetStringCount != sourceStringCount + 1) {
    throw const FormatException(
      'Visual routing supports the same number of strings or one added string.',
    );
  }
  if (routes.length != sourceStringCount) {
    throw const FormatException('Every source string needs exactly one route.');
  }
  final sorted = [...routes]
    ..sort((left, right) => left.sourceString.compareTo(right.sourceString));
  var previousTarget = -1;
  for (var index = 0; index < sorted.length; index += 1) {
    final route = sorted[index];
    if (route.sourceString != index ||
        route.targetString < 0 ||
        route.targetString >= targetStringCount ||
        route.targetString <= previousTarget) {
      throw const FormatException(
        'String routes must be complete, unique, and preserve string order.',
      );
    }
    previousTarget = route.targetString;
  }
}
