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

/// Provides recoverable source pixels around an already cropped row.
///
/// The crop editor previously displayed only [crop], so moving its bottom edge
/// to 100% could never reveal a tie, sustain, or rhythm mark already excluded
/// by automatic row detection. Keep the current row as the initial selection
/// while exposing a bounded amount of the nondestructive source page on every
/// side. The larger vertical allowance covers below-staff notation without
/// turning the editor back into a full-page crop tool.
NormalizedRect editableVisualCropViewport(NormalizedRect crop) {
  final horizontalMargin = (crop.width * 0.04).clamp(0.01, 0.04);
  final verticalMargin = (crop.height * 0.50).clamp(0.02, 0.08);
  return NormalizedRect(
    (crop.left - horizontalMargin).clamp(0.0, 1.0),
    (crop.top - verticalMargin).clamp(0.0, 1.0),
    (crop.right + horizontalMargin).clamp(0.0, 1.0),
    (crop.bottom + verticalMargin).clamp(0.0, 1.0),
  );
}
