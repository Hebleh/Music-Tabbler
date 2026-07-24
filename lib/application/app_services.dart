import 'service_contracts.dart';

class AppServices {
  const AppServices({
    required this.library,
    required this.songVariants,
    required this.setlists,
    required this.importer,
    required this.exporter,
    required this.setlistExporter,
    required this.textRecognition,
  });

  final ChartLibrary library;
  final SongVariantLibrary songVariants;
  final SetlistLibrary setlists;
  final VisualImporter importer;
  final ChartPdfExporter exporter;
  final SetlistPdfExporter setlistExporter;
  final TextRecognitionService textRecognition;
}
