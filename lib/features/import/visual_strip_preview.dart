import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/visual_image_processor.dart';
import '../../application/service_contracts.dart';
import '../../domain/visual_chart_models.dart';

class VisualStripPreview extends StatelessWidget {
  const VisualStripPreview({
    super.key,
    required this.library,
    required this.strip,
    required this.globalTreatment,
  });

  final ChartLibrary library;
  final VisualStrip strip;
  final VisualTreatment? globalTreatment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _render(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Preview unavailable'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.memory(
          snapshot.data!,
          key: ValueKey('${strip.id}-${strip.toJson()}-$globalTreatment'),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      },
    );
  }

  Future<Uint8List> _render() async {
    final file = File(library.assetPath(strip.assetHash, strip.assetExtension));
    final bytes = await file.readAsBytes();
    return const VisualImageProcessor().process(
      bytes,
      strip,
      globalTreatment: globalTreatment,
    );
  }
}
