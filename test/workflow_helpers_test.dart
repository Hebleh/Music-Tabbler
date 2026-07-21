import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/text_recognition_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/features/import/multi_row_split_dialog.dart';

void main() {
  test('even row splitter covers the selected page region in order', () {
    const source = NormalizedRect(0.05, 0.10, 0.95, 0.90);
    final rows = evenRowRects(source, 5);

    expect(rows, hasLength(5));
    expect(rows.first.top, source.top);
    expect(rows.last.bottom, source.bottom);
    for (var index = 1; index < rows.length; index += 1) {
      expect(rows[index - 1].bottom, closeTo(rows[index].top, 0.000001));
    }
  });

  test('Songsterr-style heading suggests title and artist', () {
    final result = inferTabMetadata(const [
      'SEARCH',
      'Thank You for the Venom Bass Tab',
      'Tab',
      'REVISION FROM: 09/07/2026',
      'My Chemical Romance',
    ]);

    expect(result.$1, 'Thank You for the Venom');
    expect(result.$2, 'My Chemical Romance');
  });

  test('Japanese score heading suggests the Unicode title and subtitle', () {
    final result = inferTabMetadata(const ['太陽が欲しいだけ', '(Bass)']);

    expect(result.$1, '太陽が欲しいだけ');
    expect(result.$2, '(Bass)');
  });

  test('bass transcription heading separates artist and title', () {
    final result = inferTabMetadata(const [
      'Hitorie - one me two hearts bass transcription',
    ]);

    expect(result.$1, 'one me two hearts');
    expect(result.$2, 'Hitorie');
  });

  test('master right crop catches row edges and keeps them sticky', () {
    var rows = const [
      NormalizedRect(0, 0.1, 0.9, 0.2),
      NormalizedRect(0, 0.3, 0.8, 0.4),
    ];
    final caught = <int>{};

    rows = applyStickyMasterCrop(
      rows: rows,
      caughtRows: caught,
      value: 0.85,
      previousValue: 1,
      sourceRect: const NormalizedRect.full(),
      leftSide: false,
    );
    expect(rows[0].right, 0.85);
    expect(rows[1].right, 0.8);

    rows = applyStickyMasterCrop(
      rows: rows,
      caughtRows: caught,
      value: 0.75,
      previousValue: 0.85,
      sourceRect: const NormalizedRect.full(),
      leftSide: false,
    );
    expect(rows.map((row) => row.right), everyElement(0.75));

    rows = applyStickyMasterCrop(
      rows: rows,
      caughtRows: caught,
      value: 0.82,
      previousValue: 0.75,
      sourceRect: const NormalizedRect.full(),
      leftSide: false,
    );
    expect(rows.map((row) => row.right), everyElement(0.82));
  });

  test('master crop does not catch an uncaught edge while moving outward', () {
    const rows = [NormalizedRect(0.2, 0.1, 0.8, 0.2)];
    final caught = <int>{};

    final result = applyStickyMasterCrop(
      rows: rows,
      caughtRows: caught,
      value: 0.1,
      previousValue: 0.15,
      sourceRect: const NormalizedRect.full(),
      leftSide: true,
    );

    expect(caught, isEmpty);
    expect(result.single.left, 0.2);
  });
}
