import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/visual_manual_note_placement.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';

void main() {
  test('manual note values accept normal sustained and X modes', () {
    expect(
      formatVisualManualNoteValue(type: VisualManualNoteType.normal, fret: 12),
      '12',
    );
    expect(
      formatVisualManualNoteValue(
        type: VisualManualNoteType.sustained,
        fret: 7,
      ),
      '(7)',
    );
    expect(
      formatVisualManualNoteValue(type: VisualManualNoteType.deadNote),
      'X',
    );
    expect(
      () => formatVisualManualNoteValue(
        type: VisualManualNoteType.normal,
        fret: 37,
      ),
      throwsFormatException,
    );
  });

  const system = VisualTabSystem(
    id: 'system',
    rect: NormalizedRect(0.1, 0.2, 0.9, 0.8),
    stringLines: [0.3, 0.4, 0.5, 0.6],
    tokens: [
      VisualTabToken(
        id: 'one',
        text: '7',
        rect: NormalizedRect(0.3, 0.475, 0.32, 0.525),
        kind: VisualTabTokenKind.fret,
        stringIndex: 1,
      ),
      VisualTabToken(
        id: 'two',
        text: '12',
        rect: NormalizedRect(0.4, 0.475, 0.44, 0.525),
        kind: VisualTabTokenKind.fret,
        stringIndex: 1,
      ),
    ],
  );
  const analysis = VisualTabAnalysis(
    stripId: 'strip',
    sourceType: VisualTabSourceType.rasterOcr,
    systems: [system],
  );

  test(
    'click placement uses low-to-high string assignment and token sizing',
    () {
      final placement = placeVisualManualNote(
        analysis: analysis,
        x: 0.5,
        y: 0.59,
        text: '12',
      )!;

      expect(placement.stringIndex, 0);
      expect(
        (placement.rect.top + placement.rect.bottom) / 2,
        closeTo(0.6, 1e-9),
      );
      expect(placement.rect.width, closeTo(0.056, 0.01));
    },
  );

  test(
    'explicit string override, clamping, and fixed-size drag are stable',
    () {
      final placement = placeVisualManualNote(
        analysis: analysis,
        x: 0.99,
        y: 0.31,
        text: '(9)',
        stringOverride: 2,
      )!;
      expect(placement.stringIndex, 2);
      expect(placement.rect.right, 0.9);

      final token = VisualTabToken(
        id: 'manual',
        text: '(9)',
        rect: placement.rect,
        kind: VisualTabTokenKind.fret,
        stringIndex: 2,
        origin: VisualTabTokenOrigin.manual,
      );
      final moved = moveVisualManualNote(
        system: system,
        token: token,
        centerX: 0,
        centerY: 0.59,
      );
      expect(moved.stringIndex, 0);
      expect(moved.rect.left, 0.1);
      expect(moved.rect.width, closeTo(token.rect.width, 1e-9));
    },
  );

  test('manual gradient remains local and centered on its assigned string', () {
    const token = VisualTabToken(
      id: 'manual',
      text: '3',
      rect: NormalizedRect(0.48, 0.575, 0.52, 0.625),
      kind: VisualTabTokenKind.fret,
      stringIndex: 0,
      origin: VisualTabTokenOrigin.manual,
    );
    final gradient = manualNoteGradient(system, token);
    expect(gradient.centerX, 0.5);
    expect(gradient.left, closeTo(0.34, 1e-9));
    expect(gradient.right, closeTo(0.66, 1e-9));
    expect(gradient.lineY, 0.6);
  });
}
