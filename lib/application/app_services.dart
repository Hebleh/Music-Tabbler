import 'service_contracts.dart';

class AppServices {
  const AppServices({
    required this.library,
    required this.importer,
    required this.exporter,
    required this.textRecognition,
  });

  final ChartLibrary library;
  final VisualImporter importer;
  final ChartPdfExporter exporter;
  final TextRecognitionService textRecognition;
}
