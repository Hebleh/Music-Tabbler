import 'dart:convert';
import 'dart:math' as math;

enum VisualTreatment {
  original,
  grayscale,
  invert,
  highContrast,
  invertedHighContrast,
}

enum VisualExportDensity { original, balanced, stageReadable }

enum ProvenanceImportMethod { screenshot, pdf, other }

class SourceProvenance {
  const SourceProvenance({
    required this.url,
    required this.provider,
    this.versionName = '',
    this.importMethod = ProvenanceImportMethod.screenshot,
    this.notes = '',
  });

  final String url;
  final String provider;
  final String versionName;
  final ProvenanceImportMethod importMethod;
  final String notes;

  Map<String, Object> toJson() => {
    'url': url,
    'provider': provider,
    'versionName': versionName,
    'importMethod': importMethod.name,
    'notes': notes,
  };

  factory SourceProvenance.fromJson(Map<String, Object?> json) {
    return SourceProvenance(
      url: json['url']! as String,
      provider: json['provider'] as String? ?? '',
      versionName: json['versionName'] as String? ?? '',
      importMethod: ProvenanceImportMethod.values.byName(
        json['importMethod'] as String? ?? ProvenanceImportMethod.other.name,
      ),
      notes: json['notes'] as String? ?? '',
    );
  }
}

String normalizeSourceUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme.toLowerCase() != 'https' &&
          uri.scheme.toLowerCase() != 'http')) {
    throw const FormatException('Enter a complete http:// or https:// URL.');
  }
  return uri
      .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
      .toString();
}

String inferSourceProvider(String normalizedUrl) {
  final host = Uri.parse(normalizedUrl).host.toLowerCase();
  if (host.endsWith('songsterr.com')) return 'Songsterr';
  if (host.endsWith('ultimate-guitar.com')) return 'Ultimate Guitar';
  if (host.endsWith('youtube.com') || host == 'youtu.be') return 'YouTube';
  return host;
}

extension VisualExportDensityLabel on VisualExportDensity {
  String get label => switch (this) {
    VisualExportDensity.original => 'Original (v0.1.0)',
    VisualExportDensity.balanced => 'Balanced',
    VisualExportDensity.stageReadable => 'Stage readable',
  };

  String get description => switch (this) {
    VisualExportDensity.original =>
      'Original portrait A4 export with the v0.1.0 page planning rules.',
    VisualExportDensity.balanced =>
      'Portrait A4 with additional conservative blank-band compaction and '
          'a readable row-height guard.',
    VisualExportDensity.stageReadable =>
      'Landscape A4 for wider, larger rows, with conservative blank-band '
          'compaction and a larger row-height guard.',
  };
}

extension VisualTreatmentLabel on VisualTreatment {
  String get label => switch (this) {
    VisualTreatment.original => 'Original',
    VisualTreatment.grayscale => 'Grayscale',
    VisualTreatment.invert => 'Invert',
    VisualTreatment.highContrast => 'High contrast',
    VisualTreatment.invertedHighContrast => 'Invert + high contrast',
  };
}

class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.right, this.bottom)
    : assert(right > left && bottom > top);

  const NormalizedRect.full() : this(0, 0, 1, 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool get isFull =>
      left.abs() < 0.0000001 &&
      top.abs() < 0.0000001 &&
      (right - 1).abs() < 0.0000001 &&
      (bottom - 1).abs() < 0.0000001;

  NormalizedRect clamp() {
    final nextLeft = left.clamp(0.0, 0.99);
    final nextTop = top.clamp(0.0, 0.99);
    final nextRight = right.clamp(nextLeft + 0.01, 1.0);
    final nextBottom = bottom.clamp(nextTop + 0.01, 1.0);
    return NormalizedRect(nextLeft, nextTop, nextRight, nextBottom);
  }

  Map<String, Object> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory NormalizedRect.fromJson(Map<String, Object?> json) {
    return NormalizedRect(
      (json['left']! as num).toDouble(),
      (json['top']! as num).toDouble(),
      (json['right']! as num).toDouble(),
      (json['bottom']! as num).toDouble(),
    );
  }
}

class VisualHighlight {
  const VisualHighlight({required this.id, required this.rect});

  final String id;
  final NormalizedRect rect;

  Map<String, Object> toJson() => {'id': id, 'rect': rect.toJson()};

  factory VisualHighlight.fromJson(Map<String, Object?> json) {
    return VisualHighlight(
      id: json['id']! as String,
      rect: NormalizedRect.fromJson(
        (json['rect']! as Map).cast<String, Object?>(),
      ),
    );
  }
}

class NormalizedPoint {
  const NormalizedPoint(this.x, this.y, {this.pressure = 1});

  final double x;
  final double y;
  final double pressure;

  NormalizedPoint clamp() => NormalizedPoint(
    x.clamp(0.0, 1.0),
    y.clamp(0.0, 1.0),
    pressure: pressure.clamp(0.2, 1.0),
  );

  Map<String, Object> toJson() => {'x': x, 'y': y, 'pressure': pressure};

  factory NormalizedPoint.fromJson(Map<String, Object?> json) {
    return NormalizedPoint(
      (json['x']! as num).toDouble(),
      (json['y']! as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 1,
    ).clamp();
  }
}

class VisualAnnotationStroke {
  const VisualAnnotationStroke({
    required this.id,
    required this.points,
    this.colorArgb = 0xFFFFD740,
    this.width = 0.004,
  });

  final String id;
  final List<NormalizedPoint> points;
  final int colorArgb;
  final double width;

  Map<String, Object> toJson() => {
    'id': id,
    'points': [for (final point in points) point.toJson()],
    'colorArgb': colorArgb,
    'width': width,
  };

  factory VisualAnnotationStroke.fromJson(Map<String, Object?> json) {
    return VisualAnnotationStroke(
      id: json['id']! as String,
      points: List.unmodifiable(
        (json['points']! as List).map(
          (value) =>
              NormalizedPoint.fromJson((value as Map).cast<String, Object?>()),
        ),
      ),
      colorArgb: json['colorArgb'] as int? ?? 0xFFFFD740,
      width: (json['width'] as num?)?.toDouble() ?? 0.004,
    );
  }
}

class VisualDeskewBaseGeometry {
  const VisualDeskewBaseGeometry({
    required this.crop,
    this.lyricBand,
    this.highlights = const [],
    this.annotations = const [],
  });

  final NormalizedRect crop;
  final NormalizedRect? lyricBand;
  final List<VisualHighlight> highlights;
  final List<VisualAnnotationStroke> annotations;

  Map<String, Object?> toJson() => {
    'crop': crop.toJson(),
    'lyricBand': lyricBand?.toJson(),
    'highlights': highlights.map((item) => item.toJson()).toList(),
    'annotations': annotations.map((item) => item.toJson()).toList(),
  };

  factory VisualDeskewBaseGeometry.fromJson(Map<String, Object?> json) {
    final lyricBandJson = json['lyricBand'];
    return VisualDeskewBaseGeometry(
      crop: NormalizedRect.fromJson(
        (json['crop']! as Map).cast<String, Object?>(),
      ),
      lyricBand: lyricBandJson == null
          ? null
          : NormalizedRect.fromJson(
              (lyricBandJson as Map).cast<String, Object?>(),
            ),
      highlights: ((json['highlights'] as List?) ?? const [])
          .map(
            (item) =>
                VisualHighlight.fromJson((item as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      annotations: ((json['annotations'] as List?) ?? const [])
          .map(
            (item) => VisualAnnotationStroke.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }
}

class VisualStrip {
  const VisualStrip({
    required this.id,
    required this.assetHash,
    required this.assetExtension,
    required this.pixelWidth,
    required this.pixelHeight,
    this.sourceAssetHash,
    this.sourcePage,
    this.crop = const NormalizedRect.full(),
    this.treatment = VisualTreatment.original,
    this.lyricBand,
    this.lyricContrast = 1,
    this.highlights = const [],
    this.annotations = const [],
    this.annotationsVisible = true,
    this.includeAnnotationsInPdf = false,
    this.deskewDegrees = 0,
    this.deskewBaseGeometry,
    this.splitMasterLeft,
    this.splitMasterRight,
  });

  final String id;
  final String assetHash;
  final String assetExtension;
  final int pixelWidth;
  final int pixelHeight;
  final String? sourceAssetHash;
  final int? sourcePage;
  final NormalizedRect crop;
  final VisualTreatment treatment;
  final NormalizedRect? lyricBand;
  final double lyricContrast;
  final List<VisualHighlight> highlights;
  final List<VisualAnnotationStroke> annotations;
  final bool annotationsVisible;
  final bool includeAnnotationsInPdf;
  final double deskewDegrees;
  final VisualDeskewBaseGeometry? deskewBaseGeometry;
  final double? splitMasterLeft;
  final double? splitMasterRight;

  double get deskewedPixelWidth {
    final radians = deskewDegrees * math.pi / 180;
    return (pixelWidth * math.cos(radians)).abs() +
        (pixelHeight * math.sin(radians)).abs();
  }

  double get deskewedPixelHeight {
    final radians = deskewDegrees * math.pi / 180;
    return (pixelWidth * math.sin(radians)).abs() +
        (pixelHeight * math.cos(radians)).abs();
  }

  double get croppedAspectRatio =>
      (deskewedPixelWidth * crop.width) / (deskewedPixelHeight * crop.height);

  VisualStrip copyWith({
    NormalizedRect? crop,
    VisualTreatment? treatment,
    NormalizedRect? lyricBand,
    bool clearLyricBand = false,
    double? lyricContrast,
    List<VisualHighlight>? highlights,
    List<VisualAnnotationStroke>? annotations,
    bool? annotationsVisible,
    bool? includeAnnotationsInPdf,
    double? deskewDegrees,
    VisualDeskewBaseGeometry? deskewBaseGeometry,
    bool clearDeskewBaseGeometry = false,
    double? splitMasterLeft,
    double? splitMasterRight,
    bool clearSplitMaster = false,
  }) {
    return VisualStrip(
      id: id,
      assetHash: assetHash,
      assetExtension: assetExtension,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      sourceAssetHash: sourceAssetHash,
      sourcePage: sourcePage,
      crop: crop ?? this.crop,
      treatment: treatment ?? this.treatment,
      lyricBand: clearLyricBand ? null : lyricBand ?? this.lyricBand,
      lyricContrast: lyricContrast ?? this.lyricContrast,
      highlights: highlights ?? this.highlights,
      annotations: annotations ?? this.annotations,
      annotationsVisible: annotationsVisible ?? this.annotationsVisible,
      includeAnnotationsInPdf:
          includeAnnotationsInPdf ?? this.includeAnnotationsInPdf,
      deskewDegrees: deskewDegrees ?? this.deskewDegrees,
      deskewBaseGeometry: clearDeskewBaseGeometry
          ? null
          : deskewBaseGeometry ?? this.deskewBaseGeometry,
      splitMasterLeft: clearSplitMaster
          ? null
          : splitMasterLeft ?? this.splitMasterLeft,
      splitMasterRight: clearSplitMaster
          ? null
          : splitMasterRight ?? this.splitMasterRight,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'assetHash': assetHash,
    'assetExtension': assetExtension,
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'sourceAssetHash': sourceAssetHash,
    'sourcePage': sourcePage,
    'crop': crop.toJson(),
    'treatment': treatment.name,
    'lyricBand': lyricBand?.toJson(),
    'lyricContrast': lyricContrast,
    'highlights': highlights.map((item) => item.toJson()).toList(),
    'annotations': annotations.map((item) => item.toJson()).toList(),
    'annotationsVisible': annotationsVisible,
    'includeAnnotationsInPdf': includeAnnotationsInPdf,
    'deskewDegrees': deskewDegrees,
    'deskewBaseGeometry': deskewBaseGeometry?.toJson(),
    'splitMasterLeft': splitMasterLeft,
    'splitMasterRight': splitMasterRight,
  };

  factory VisualStrip.fromJson(Map<String, Object?> json) {
    final lyricBandJson = json['lyricBand'];
    return VisualStrip(
      id: json['id']! as String,
      assetHash: json['assetHash']! as String,
      assetExtension: json['assetExtension']! as String,
      pixelWidth: json['pixelWidth']! as int,
      pixelHeight: json['pixelHeight']! as int,
      sourceAssetHash: json['sourceAssetHash'] as String?,
      sourcePage: json['sourcePage'] as int?,
      crop: NormalizedRect.fromJson(
        (json['crop']! as Map).cast<String, Object?>(),
      ),
      treatment: VisualTreatment.values.byName(json['treatment']! as String),
      lyricBand: lyricBandJson == null
          ? null
          : NormalizedRect.fromJson(
              (lyricBandJson as Map).cast<String, Object?>(),
            ),
      lyricContrast: (json['lyricContrast']! as num).toDouble(),
      highlights: (json['highlights']! as List)
          .map(
            (item) =>
                VisualHighlight.fromJson((item as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      annotations: ((json['annotations'] as List?) ?? const [])
          .map(
            (item) => VisualAnnotationStroke.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      annotationsVisible: json['annotationsVisible'] as bool? ?? true,
      includeAnnotationsInPdf:
          json['includeAnnotationsInPdf'] as bool? ?? false,
      deskewDegrees: (json['deskewDegrees'] as num?)?.toDouble() ?? 0,
      deskewBaseGeometry: json['deskewBaseGeometry'] == null
          ? null
          : VisualDeskewBaseGeometry.fromJson(
              (json['deskewBaseGeometry']! as Map).cast<String, Object?>(),
            ),
      splitMasterLeft: (json['splitMasterLeft'] as num?)?.toDouble(),
      splitMasterRight: (json['splitMasterRight'] as num?)?.toDouble(),
    );
  }
}

class VisualTabTransformRecord {
  const VisualTabTransformRecord({
    required this.id,
    required this.appliedAt,
    required this.baseStrips,
    required this.configuration,
    required this.analyses,
    this.audit = const [],
  });

  final String id;
  final DateTime appliedAt;
  final List<VisualStrip> baseStrips;
  final Map<String, Object?> configuration;
  final List<Map<String, Object?>> analyses;
  final List<String> audit;

  Map<String, Object?> toJson() => {
    'id': id,
    'appliedAt': appliedAt.toIso8601String(),
    'baseStrips': baseStrips.map((strip) => strip.toJson()).toList(),
    'configuration': configuration,
    'analyses': analyses,
    'audit': audit,
  };

  factory VisualTabTransformRecord.fromJson(Map<String, Object?> json) {
    return VisualTabTransformRecord(
      id: json['id']! as String,
      appliedAt: DateTime.parse(json['appliedAt']! as String),
      baseStrips: ((json['baseStrips'] as List?) ?? const [])
          .map(
            (value) =>
                VisualStrip.fromJson((value as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      configuration: (json['configuration']! as Map).cast<String, Object?>(),
      analyses: ((json['analyses'] as List?) ?? const [])
          .map((value) => (value as Map).cast<String, Object?>())
          .toList(growable: false),
      audit: ((json['audit'] as List?) ?? const []).cast<String>().toList(
        growable: false,
      ),
    );
  }
}

class VisualChartDraft {
  const VisualChartDraft({
    required this.id,
    required this.title,
    required this.artist,
    required this.createdAt,
    required this.updatedAt,
    this.showHeader = true,
    this.exportDensity = VisualExportDensity.original,
    this.globalTreatment,
    this.provenance,
    this.visualTabTransform,
    this.strips = const [],
  });

  final String id;
  final String title;
  final String artist;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool showHeader;
  final VisualExportDensity exportDensity;
  final VisualTreatment? globalTreatment;
  final SourceProvenance? provenance;
  final VisualTabTransformRecord? visualTabTransform;
  final List<VisualStrip> strips;

  bool get isUntitled {
    final normalized = title.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'untitled' ||
        normalized == 'untitled chart';
  }

  String get displayTitle {
    final trimmedArtist = artist.trim();
    return isUntitled && trimmedArtist.isNotEmpty ? trimmedArtist : title;
  }

  String get displayArtist => isUntitled ? '' : artist.trim();

  Iterable<VisualStrip> get allReferencedStrips sync* {
    yield* strips;
    final transform = visualTabTransform;
    if (transform != null) yield* transform.baseStrips;
  }

  VisualChartDraft copyWith({
    String? id,
    String? title,
    String? artist,
    bool? showHeader,
    VisualExportDensity? exportDensity,
    VisualTreatment? globalTreatment,
    bool clearGlobalTreatment = false,
    SourceProvenance? provenance,
    bool clearProvenance = false,
    VisualTabTransformRecord? visualTabTransform,
    bool clearVisualTabTransform = false,
    List<VisualStrip>? strips,
    DateTime? updatedAt,
  }) {
    return VisualChartDraft(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      showHeader: showHeader ?? this.showHeader,
      exportDensity: exportDensity ?? this.exportDensity,
      globalTreatment: clearGlobalTreatment
          ? null
          : globalTreatment ?? this.globalTreatment,
      provenance: clearProvenance ? null : provenance ?? this.provenance,
      visualTabTransform: clearVisualTabTransform
          ? null
          : visualTabTransform ?? this.visualTabTransform,
      strips: strips ?? this.strips,
    );
  }

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'id': id,
    'title': title,
    'artist': artist,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'showHeader': showHeader,
    'exportDensity': exportDensity.name,
    'globalTreatment': globalTreatment?.name,
    'provenance': provenance?.toJson(),
    'visualTabTransform': visualTabTransform?.toJson(),
    'strips': strips.map((strip) => strip.toJson()).toList(),
  };

  factory VisualChartDraft.decode(String value) {
    return VisualChartDraft.fromJson(
      (jsonDecode(value) as Map).cast<String, Object?>(),
    );
  }

  factory VisualChartDraft.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'] as int?;
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw const FormatException('Unsupported visual chart schema.');
    }
    final treatment = json['globalTreatment'] as String?;
    final densityName = json['exportDensity'] as String?;
    final provenance = json['provenance'];
    final visualTabTransform = json['visualTabTransform'];
    return VisualChartDraft(
      id: json['id']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      showHeader: json['showHeader']! as bool,
      exportDensity: densityName == null
          ? VisualExportDensity.original
          : VisualExportDensity.values.byName(densityName),
      globalTreatment: treatment == null
          ? null
          : VisualTreatment.values.byName(treatment),
      provenance: provenance == null
          ? null
          : SourceProvenance.fromJson(
              (provenance as Map).cast<String, Object?>(),
            ),
      visualTabTransform: visualTabTransform == null
          ? null
          : VisualTabTransformRecord.fromJson(
              (visualTabTransform as Map).cast<String, Object?>(),
            ),
      strips: (json['strips']! as List)
          .map(
            (item) =>
                VisualStrip.fromJson((item as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
    );
  }
}

class IdFactory {
  IdFactory._();

  static int _sequence = 0;

  static String next(String prefix) {
    _sequence += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_sequence';
  }
}
