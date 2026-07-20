import 'service_contracts.dart';

class AppServices {
  const AppServices({
    required this.library,
    required this.importer,
    required this.exporter,
  });

  final ChartLibrary library;
  final VisualImporter importer;
  final ChartPdfExporter exporter;
}
