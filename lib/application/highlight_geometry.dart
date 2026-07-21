import '../domain/visual_chart_models.dart';

NormalizedRect? assetRectToCropLocal(NormalizedRect rect, NormalizedRect crop) {
  final left = rect.left > crop.left ? rect.left : crop.left;
  final top = rect.top > crop.top ? rect.top : crop.top;
  final right = rect.right < crop.right ? rect.right : crop.right;
  final bottom = rect.bottom < crop.bottom ? rect.bottom : crop.bottom;
  if (right <= left || bottom <= top) return null;
  return NormalizedRect(
    (left - crop.left) / crop.width,
    (top - crop.top) / crop.height,
    (right - crop.left) / crop.width,
    (bottom - crop.top) / crop.height,
  ).clamp();
}

NormalizedRect cropLocalRectToAsset(NormalizedRect rect, NormalizedRect crop) {
  return NormalizedRect(
    crop.left + rect.left * crop.width,
    crop.top + rect.top * crop.height,
    crop.left + rect.right * crop.width,
    crop.top + rect.bottom * crop.height,
  ).clamp();
}
