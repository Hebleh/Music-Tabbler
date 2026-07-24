import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';

Uint8List flattenVisualAnnotations(
  Uint8List source,
  List<VisualAnnotationStroke> annotations, {
  required bool include,
}) {
  if (!include || annotations.isEmpty) return source;
  final image = img.decodePng(source);
  if (image == null) return source;
  for (final stroke in annotations) {
    if (stroke.points.length < 2) continue;
    final color = img.ColorRgba8(
      (stroke.colorArgb >> 16) & 0xFF,
      (stroke.colorArgb >> 8) & 0xFF,
      stroke.colorArgb & 0xFF,
      (stroke.colorArgb >> 24) & 0xFF,
    );
    final thickness = (stroke.width * image.width).round().clamp(1, 24);
    for (var index = 1; index < stroke.points.length; index += 1) {
      final from = stroke.points[index - 1];
      final to = stroke.points[index];
      img.drawLine(
        image,
        x1: (from.x * (image.width - 1)).round(),
        y1: (from.y * (image.height - 1)).round(),
        x2: (to.x * (image.width - 1)).round(),
        y2: (to.y * (image.height - 1)).round(),
        color: color,
        thickness: thickness,
        antialias: true,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image, level: 3));
}
