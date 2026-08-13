import 'dart:typed_data';

import '../domain/visual_chart_models.dart';

abstract interface class VisualImporter {
  Future<List<VisualStrip>> pickImages();
  Future<List<VisualStrip>> pickPdf();
  Future<List<VisualStrip>> importPdfBytes(Uint8List bytes);
  Future<List<VisualStrip>> pasteImages();
  Future<List<VisualStrip>> importPaths(Iterable<String> paths);
}

class IncomingPdf {
  const IncomingPdf({required this.bytes, this.fileName});

  final Uint8List bytes;
  final String? fileName;
}

/// Receives user-initiated PDF shares from the host platform.
abstract interface class IncomingPdfReceiver {
  Stream<void> get available;
  Future<IncomingPdf?> takePendingPdf();
}

class RecognizedTextRegion {
  const RecognizedTextRegion({
    required this.text,
    required this.rect,
    this.confidence = 1,
  });

  final String text;
  final NormalizedRect rect;
  final double confidence;
}

class MetadataSuggestion {
  const MetadataSuggestion({this.title, this.artist, this.regions = const []});

  final String? title;
  final String? artist;
  final List<RecognizedTextRegion> regions;
}

abstract interface class TextRecognitionService {
  Future<MetadataSuggestion> recognize(VisualStrip strip);
}

/// Optional capability for OCR callers that need purpose-specific image
/// preprocessing without first installing a temporary library asset.
abstract interface class PreparedTextRecognitionService {
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes);
}

class ImportCancelled implements Exception {
  const ImportCancelled();
}

class VisualImportException implements Exception {
  const VisualImportException(this.message);
  final String message;

  @override
  String toString() => message;
}
