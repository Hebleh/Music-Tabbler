import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'application/app_services.dart';
import 'application/pdf_export_service.dart';
import 'application/text_recognition_service.dart';
import 'application/visual_import_service.dart';
import 'infrastructure/local_library.dart';
import 'infrastructure/device_preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final library = await LocalLibrary.open();
    final supportDirectory = await getApplicationSupportDirectory();
    final preferences = FileDevicePreferencesStore(
      File(p.join(supportDirectory.path, 'device-preferences.json')),
    );
    final initialPreferences = await preferences.load();
    final pdfExporter = PdfExportService(library);
    runApp(
      MusicTabblerApp(
        initialPreferences: initialPreferences,
        services: AppServices(
          library: library,
          songVariants: library,
          setlists: library,
          importer: VisualImportService(library),
          exporter: pdfExporter,
          setlistExporter: pdfExporter,
          performanceDeckBuilder: pdfExporter,
          textRecognition: NativeTextRecognitionService(library),
          preferences: preferences,
        ),
      ),
    );
  } catch (error) {
    runApp(_StartupErrorApp(error: error));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 52),
                const SizedBox(height: 12),
                const Text('Music Tabbler could not open its local library.'),
                const SizedBox(height: 8),
                SelectableText(error.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
