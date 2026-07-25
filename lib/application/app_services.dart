import 'service_contracts.dart';

class AppServices {
  const AppServices({
    required this.library,
    required this.songVariants,
    required this.semanticCharts,
    required this.setlists,
    required this.importer,
    required this.exporter,
    required this.semanticExporter,
    required this.setlistExporter,
    required this.performanceDeckBuilder,
    required this.textRecognition,
    required this.preferences,
    required this.performanceMode,
    this.externalUrlOpener,
    this.songBundles,
    this.libraryState,
  });

  final ChartLibrary library;
  final SongVariantLibrary songVariants;
  final SemanticChartLibrary semanticCharts;
  final SetlistLibrary setlists;
  final VisualImporter importer;
  final ChartPdfExporter exporter;
  final SemanticChartPdfExporter semanticExporter;
  final SetlistPdfExporter setlistExporter;
  final PerformanceDeckBuilder performanceDeckBuilder;
  final TextRecognitionService textRecognition;
  final DevicePreferencesStore preferences;
  final PerformanceModeController performanceMode;
  final ExternalUrlOpener? externalUrlOpener;
  final SongBundleTransfer? songBundles;
  final LibraryStateTransfer? libraryState;
}
