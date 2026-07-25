import 'dart:typed_data';

import '../domain/visual_chart_models.dart';

enum PerformanceElementKind { header, boundary, strip, placeholder }

class PerformanceDeckElement {
  const PerformanceDeckElement({
    required this.kind,
    required this.entryIndex,
    required this.entryId,
    required this.width,
    required this.height,
    this.chartVariantId,
    this.sourceStripId,
    this.sourceRowRect,
    this.title,
    this.artist,
    this.rowIndex,
    this.imageBytes,
    this.annotations = const [],
    this.annotationsVisible = true,
    this.includeAnnotationsInPdf = false,
  });

  final PerformanceElementKind kind;
  final int entryIndex;
  final String entryId;
  final String? chartVariantId;
  final String? sourceStripId;
  final NormalizedRect? sourceRowRect;
  final String? title;
  final String? artist;
  final int? rowIndex;
  final double width;
  final double height;
  final Uint8List? imageBytes;
  final List<VisualAnnotationStroke> annotations;
  final bool annotationsVisible;
  final bool includeAnnotationsInPdf;

  PerformanceDeckElement copyWith({
    List<VisualAnnotationStroke>? annotations,
    bool? annotationsVisible,
    bool? includeAnnotationsInPdf,
  }) {
    return PerformanceDeckElement(
      kind: kind,
      entryIndex: entryIndex,
      entryId: entryId,
      width: width,
      height: height,
      chartVariantId: chartVariantId,
      sourceStripId: sourceStripId,
      sourceRowRect: sourceRowRect,
      title: title,
      artist: artist,
      rowIndex: rowIndex,
      imageBytes: imageBytes,
      annotations: annotations ?? this.annotations,
      annotationsVisible: annotationsVisible ?? this.annotationsVisible,
      includeAnnotationsInPdf:
          includeAnnotationsInPdf ?? this.includeAnnotationsInPdf,
    );
  }

  Map<String, Object?> toMessage() => {
    'kind': kind.name,
    'entryIndex': entryIndex,
    'entryId': entryId,
    'chartVariantId': chartVariantId,
    'sourceStripId': sourceStripId,
    'sourceRowRect': sourceRowRect?.toJson(),
    'title': title,
    'artist': artist,
    'rowIndex': rowIndex,
    'width': width,
    'height': height,
    'imageBytes': imageBytes,
    'annotations': [for (final stroke in annotations) stroke.toJson()],
    'annotationsVisible': annotationsVisible,
    'includeAnnotationsInPdf': includeAnnotationsInPdf,
  };

  factory PerformanceDeckElement.fromMessage(Map<String, Object?> message) {
    return PerformanceDeckElement(
      kind: PerformanceElementKind.values.byName(message['kind']! as String),
      entryIndex: message['entryIndex']! as int,
      entryId: message['entryId']! as String,
      chartVariantId: message['chartVariantId'] as String?,
      sourceStripId: message['sourceStripId'] as String?,
      sourceRowRect: message['sourceRowRect'] == null
          ? null
          : NormalizedRect.fromJson(
              (message['sourceRowRect'] as Map).cast<String, Object?>(),
            ),
      title: message['title'] as String?,
      artist: message['artist'] as String?,
      rowIndex: message['rowIndex'] as int?,
      width: (message['width']! as num).toDouble(),
      height: (message['height']! as num).toDouble(),
      imageBytes: message['imageBytes'] as Uint8List?,
      annotations: List.unmodifiable(
        ((message['annotations'] as List?) ?? const []).map(
          (value) => VisualAnnotationStroke.fromJson(
            (value as Map).cast<String, Object?>(),
          ),
        ),
      ),
      annotationsVisible: message['annotationsVisible'] as bool? ?? true,
      includeAnnotationsInPdf:
          message['includeAnnotationsInPdf'] as bool? ?? false,
    );
  }
}

class PerformanceDeckPage {
  const PerformanceDeckPage({
    required this.id,
    required this.index,
    required this.elements,
  });

  final String id;
  final int index;
  final List<PerformanceDeckElement> elements;

  int get firstEntryIndex => elements.first.entryIndex;
  int get lastEntryIndex => elements.last.entryIndex;

  Map<String, Object?> toMessage() => {
    'id': id,
    'index': index,
    'elements': [for (final element in elements) element.toMessage()],
  };

  factory PerformanceDeckPage.fromMessage(Map<String, Object?> message) {
    return PerformanceDeckPage(
      id: message['id']! as String,
      index: message['index']! as int,
      elements: List.unmodifiable(
        (message['elements']! as List).map(
          (value) => PerformanceDeckElement.fromMessage(
            (value as Map).cast<String, Object?>(),
          ),
        ),
      ),
    );
  }
}

class PerformanceDeck {
  const PerformanceDeck({
    required this.setlistId,
    required this.setlistName,
    required this.density,
    required this.pageWidth,
    required this.pageHeight,
    required this.margin,
    required this.gap,
    required this.pages,
  });

  final String setlistId;
  final String setlistName;
  final VisualExportDensity density;
  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double gap;
  final List<PerformanceDeckPage> pages;

  PerformanceDeck copyWith({List<PerformanceDeckPage>? pages}) {
    return PerformanceDeck(
      setlistId: setlistId,
      setlistName: setlistName,
      density: density,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      margin: margin,
      gap: gap,
      pages: pages ?? this.pages,
    );
  }

  Map<String, Object?> toMessage() => {
    'setlistId': setlistId,
    'setlistName': setlistName,
    'density': density.name,
    'pageWidth': pageWidth,
    'pageHeight': pageHeight,
    'margin': margin,
    'gap': gap,
    'pages': [for (final page in pages) page.toMessage()],
  };

  factory PerformanceDeck.fromMessage(Map<String, Object?> message) {
    return PerformanceDeck(
      setlistId: message['setlistId']! as String,
      setlistName: message['setlistName']! as String,
      density: VisualExportDensity.values.byName(message['density']! as String),
      pageWidth: (message['pageWidth']! as num).toDouble(),
      pageHeight: (message['pageHeight']! as num).toDouble(),
      margin: (message['margin']! as num).toDouble(),
      gap: (message['gap']! as num).toDouble(),
      pages: List.unmodifiable(
        (message['pages']! as List).map(
          (value) => PerformanceDeckPage.fromMessage(
            (value as Map).cast<String, Object?>(),
          ),
        ),
      ),
    );
  }
}

class PerformanceDeckCursor {
  const PerformanceDeckCursor({required this.pageCount, this.pageIndex = 0})
    : assert(pageCount >= 0),
      assert(pageCount == 0 ? pageIndex == 0 : pageIndex < pageCount);

  final int pageCount;
  final int pageIndex;

  bool get canAdvance => pageIndex + 1 < pageCount;
  bool get canRetreat => pageIndex > 0;

  PerformanceDeckCursor advance() => canAdvance
      ? PerformanceDeckCursor(pageCount: pageCount, pageIndex: pageIndex + 1)
      : this;

  PerformanceDeckCursor retreat() => canRetreat
      ? PerformanceDeckCursor(pageCount: pageCount, pageIndex: pageIndex - 1)
      : this;
}
