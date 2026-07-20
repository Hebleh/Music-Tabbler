import 'package:flutter/material.dart';

import 'app.dart';
import 'application/app_services.dart';
import 'application/pdf_export_service.dart';
import 'application/text_recognition_service.dart';
import 'application/visual_import_service.dart';
import 'infrastructure/local_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final library = await LocalLibrary.open();
    runApp(
      MusicTabblerApp(
        services: AppServices(
          library: library,
          importer: VisualImportService(library),
          exporter: PdfExportService(library),
          textRecognition: NativeTextRecognitionService(library),
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
