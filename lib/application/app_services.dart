import 'service_contracts.dart';

class AppServices {
  const AppServices({
    required this.library,
    required this.songVariants,
    required this.setlists,
    required this.importer,
    required this.exporter,
    required this.setlistExporter,
    required this.performanceDeckBuilder,
    required this.textRecognition,
    required this.preferences,
    required this.performanceMode,
  });

  final ChartLibrary library;
  final SongVariantLibrary songVariants;
  final SetlistLibrary setlists;
  final VisualImporter importer;
  final ChartPdfExporter exporter;
  final SetlistPdfExporter setlistExporter;
  final PerformanceDeckBuilder performanceDeckBuilder;
  final TextRecognitionService textRecognition;
  final DevicePreferencesStore preferences;
  final PerformanceModeController performanceMode;
}
