import '../domain/music_models.dart';
import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';
import 'highlight_geometry.dart';
import 'semantic_recognition_service.dart';

/// Converts a reviewed visual transform into semantic recognition inputs.
///
/// Each detected bar interval becomes one semantic measure. Keeping an entire
/// visual row as one measure compresses several real bars into the same
/// four-beat space and makes otherwise separate fret proposals overlap.
List<RecognitionStripInput>? reviewedVisualRecognitionInputs({
  required VisualTabTransformRecord record,
  required BassTuning tuning,
}) {
  final configuration = VisualTabTransformConfiguration.fromJson(
    record.configuration,
  );
  if (configuration.targetLabels.length != tuning.strings.length) return null;

  final analyses = {
    for (final value in record.analyses)
      VisualTabAnalysis.fromJson(value).stripId: VisualTabAnalysis.fromJson(
        value,
      ),
  };
  final routes = {
    for (final route in configuration.routes) route.sourceString: route,
  };
  final inputs = <RecognitionStripInput>[];

  for (final strip in record.baseStrips) {
    final analysis = analyses[strip.id];
    if (analysis == null) return null;
    for (final system in analysis.systems) {
      final spans = _measureSpans(system);
      for (final span in spans) {
        final candidates = <ReviewedFretCandidateInput>[];
        for (final token in system.tokens) {
          final sourceString = token.stringIndex;
          if (!token.enabled || !token.isFretLike || sourceString == null) {
            continue;
          }
          final centerX = (token.rect.left + token.rect.right) / 2;
          if (!_belongsToSpan(centerX, span, spans.last)) continue;
          final route = routes[sourceString];
          if (route == null) continue;
          final deadNote =
              token.kind == VisualTabTokenKind.deadNote ||
              token.text.trim().toLowerCase() == 'x';
          final sourceFret = deadNote ? 0 : _reviewedFret(token.text);
          if (sourceFret == null) continue;
          final targetFret = deadNote ? 0 : sourceFret + route.effectiveOffset;
          if (targetFret < 0 || targetFret > 36) continue;
          candidates.add(
            ReviewedFretCandidateInput(
              fret: targetFret,
              stringIndex: route.targetString,
              rect: _rectRelativeToSpan(token.rect, span),
              sourceRect: cropLocalRectToAsset(token.rect, strip.crop),
              confidence: token.confidence,
              deadNote: deadNote,
            ),
          );
        }
        inputs.add(
          RecognitionStripInput(
            sourceId: '${strip.assetHash}.${strip.assetExtension}',
            regions: const [],
            stringCount: tuning.strings.length,
            tabBand: const NormalizedRect.full(),
            sourceBand: cropLocalRectToAsset(
              NormalizedRect(
                span.left,
                system.rect.top,
                span.right,
                system.rect.bottom,
              ),
              strip.crop,
            ),
            reviewedFretCandidates: candidates,
          ),
        );
      }
    }
  }
  return inputs;
}

List<_HorizontalSpan> _measureSpans(VisualTabSystem system) {
  final boundaries = <double>[
    system.rect.left,
    ...system.barLines.where(
      (value) =>
          value > system.rect.left + 0.002 && value < system.rect.right - 0.002,
    ),
    system.rect.right,
  ]..sort();
  final unique = <double>[];
  for (final boundary in boundaries) {
    if (unique.isEmpty || (boundary - unique.last).abs() > 0.006) {
      unique.add(boundary);
    }
  }
  final spans = <_HorizontalSpan>[];
  for (var index = 0; index + 1 < unique.length; index += 1) {
    if (unique[index + 1] - unique[index] < 0.025) continue;
    spans.add(_HorizontalSpan(unique[index], unique[index + 1]));
  }
  return spans.isEmpty
      ? [_HorizontalSpan(system.rect.left, system.rect.right)]
      : spans;
}

bool _belongsToSpan(
  double centerX,
  _HorizontalSpan span,
  _HorizontalSpan last,
) =>
    centerX >= span.left &&
    (centerX < span.right || (identical(span, last) && centerX <= span.right));

NormalizedRect _rectRelativeToSpan(NormalizedRect rect, _HorizontalSpan span) {
  final width = span.right - span.left;
  final left = ((rect.left - span.left) / width).clamp(0.0, 1.0);
  final right = ((rect.right - span.left) / width).clamp(left, 1.0);
  return NormalizedRect(left, rect.top, right, rect.bottom);
}

int? _reviewedFret(String text) {
  final trimmed = text.trim();
  final digits = trimmed.startsWith('(') && trimmed.endsWith(')')
      ? trimmed.substring(1, trimmed.length - 1)
      : trimmed;
  return int.tryParse(digits);
}

class _HorizontalSpan {
  const _HorizontalSpan(this.left, this.right);

  final double left;
  final double right;
}
