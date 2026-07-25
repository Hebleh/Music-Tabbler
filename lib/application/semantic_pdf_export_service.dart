import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/music_models.dart';
import 'pdf_export_service.dart';
import 'semantic_layout.dart';
import 'service_contracts.dart';

class SemanticPdfExportService implements SemanticChartPdfExporter {
  const SemanticPdfExportService({
    this.layout = const SemanticLayoutEngine(),
    this.writer = const StagedPdfFileWriter(),
  });

  final SemanticLayoutEngine layout;
  final StagedPdfFileWriter writer;

  @override
  Future<Uint8List> exportSemanticBytes(
    SongChart chart, {
    required bool showTitle,
    required bool showTab,
    required bool showNotation,
  }) async {
    final plan = layout.build(
      chart,
      showTitle: showTitle,
      showTab: showTab,
      showNotation: showNotation,
    );
    const margin = 8.0;
    final contentWidth = PdfPageFormat.a4.width - margin * 2;
    final scale = contentWidth / plan.width;
    final maximumLogicalHeight = (PdfPageFormat.a4.height - margin * 2) / scale;
    final document = pw.Document();
    for (final range in plan.paginate(maximumLogicalHeight)) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(margin),
          build: (_) => pw.Stack(
            children: [
              for (final primitive in plan.primitives)
                if (_belongsToPage(primitive, range.start, range.end))
                  _renderPrimitive(primitive, range.start, scale),
            ],
          ),
        ),
      );
    }
    return document.save();
  }

  @override
  Future<String?> exportSemanticWithPicker(
    SongChart chart, {
    required bool showTitle,
    required bool showTab,
    required bool showNotation,
  }) async {
    final bytes = await exportSemanticBytes(
      chart,
      showTitle: showTitle,
      showTab: showTab,
      showNotation: showNotation,
    );
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export semantic chart as A4 PDF',
      fileName: '${_safeName(chart.title)}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (destination == null) return null;
    await writer.write(destination, bytes);
    return destination;
  }

  bool _belongsToPage(SemanticPrimitive primitive, double start, double end) {
    final y = switch (primitive) {
      SemanticLinePrimitive() => primitive.y1,
      SemanticTextPrimitive() => primitive.y,
      SemanticEllipsePrimitive() => primitive.y,
    };
    return y >= start && y < end;
  }

  pw.Widget _renderPrimitive(
    SemanticPrimitive primitive,
    double pageStart,
    double scale,
  ) {
    switch (primitive) {
      case SemanticTextPrimitive():
        return pw.Positioned(
          left: primitive.x * scale,
          top: (primitive.y - pageStart) * scale,
          child: pw.Text(
            primitive.text,
            style: pw.TextStyle(
              fontSize: primitive.size * scale,
              fontWeight:
                  primitive.role == SemanticTextRole.title ||
                      primitive.role == SemanticTextRole.fret ||
                      primitive.role == SemanticTextRole.backingLyric ||
                      primitive.role == SemanticTextRole.section
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: primitive.role == SemanticTextRole.backingLyric
                  ? PdfColors.deepOrange
                  : primitive.role == SemanticTextRole.lyric
                  ? PdfColors.grey700
                  : PdfColors.black,
            ),
          ),
        );
      case SemanticEllipsePrimitive():
        return pw.Positioned(
          left: (primitive.x - primitive.width / 2) * scale,
          top: (primitive.y - pageStart - primitive.height / 2) * scale,
          child: pw.Container(
            width: primitive.width * scale,
            height: primitive.height * scale,
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              shape: pw.BoxShape.circle,
            ),
          ),
        );
      case SemanticLinePrimitive():
        final isVertical =
            (primitive.x2 - primitive.x1).abs() <
            (primitive.y2 - primitive.y1).abs();
        return pw.Positioned(
          left: primitive.x1 * scale,
          top: (primitive.y1 - pageStart) * scale,
          child: pw.Container(
            width: isVertical
                ? primitive.width * scale
                : (primitive.x2 - primitive.x1).abs() * scale,
            height: isVertical
                ? (primitive.y2 - primitive.y1).abs() * scale
                : primitive.width * scale,
            color:
                primitive.role == SemanticLineRole.staff ||
                    primitive.role == SemanticLineRole.tab
                ? PdfColors.grey700
                : PdfColors.black,
          ),
        );
    }
  }

  String _safeName(String title) {
    final value = title.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return value.isEmpty ? 'semantic-chart' : value;
  }
}
