import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/service_contracts.dart';
import '../../application/visual_image_processor.dart';
import '../../domain/visual_chart_models.dart';

class VisualStripPreview extends StatefulWidget {
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
  State<VisualStripPreview> createState() => _VisualStripPreviewState();
}

class _VisualStripPreviewState extends State<VisualStripPreview> {
  late Future<Uint8List> _future;
  late String _cacheKey;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant VisualStripPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _keyFor(widget.strip, widget.globalTreatment);
    if (nextKey != _cacheKey) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferredHeight = visualStripPreviewHeight(
          constraints.maxWidth,
          widget.strip.croppedAspectRatio,
        );
        final height = preferredHeight.clamp(
          constraints.minHeight,
          constraints.maxHeight,
        );
        return SizedBox(
          height: height,
          child: RepaintBoundary(
            child: FutureBuilder<Uint8List>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Preview unavailable'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _refresh() {
    _cacheKey = _keyFor(widget.strip, widget.globalTreatment);
    _future = _PreviewCache.load(_cacheKey, () async {
      final file = File(
        widget.library.assetPath(
          widget.strip.assetHash,
          widget.strip.assetExtension,
        ),
      );
      final bytes = await file.readAsBytes();
      return compute(_renderPreview, <String, Object?>{
        'bytes': bytes,
        'strip': widget.strip.toJson(),
        'globalTreatment': widget.globalTreatment?.name,
      });
    });
  }

  String _keyFor(VisualStrip strip, VisualTreatment? treatment) =>
      '${strip.assetHash}:${jsonEncode(strip.toJson())}:${treatment?.name}';
}

class _PreviewCache {
  static const maxEntries = 48;
  static final Map<String, Future<Uint8List>> _items = {};

  static Future<Uint8List> load(
    String key,
    Future<Uint8List> Function() create,
  ) {
    final existing = _items.remove(key);
    if (existing != null) {
      _items[key] = existing;
      return existing;
    }
    final future = create();
    _items[key] = future;
    if (_items.length > maxEntries) _items.remove(_items.keys.first);
    future.catchError((Object _) {
      _items.remove(key);
      return Uint8List(0);
    });
    return future;
  }
}

double visualStripPreviewHeight(double availableWidth, double aspectRatio) {
  if (!availableWidth.isFinite || availableWidth <= 0) return 90;
  final safeAspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1;
  return (availableWidth / safeAspect).clamp(90.0, 320.0);
}

Uint8List _renderPreview(Map<String, Object?> request) {
  final strip = VisualStrip.fromJson(
    (request['strip']! as Map).cast<String, Object?>(),
  );
  final treatmentName = request['globalTreatment'] as String?;
  return const VisualImageProcessor().process(
    request['bytes']! as Uint8List,
    strip,
    globalTreatment: treatmentName == null
        ? null
        : VisualTreatment.values.byName(treatmentName),
    maxWidth: 1400,
  );
}
