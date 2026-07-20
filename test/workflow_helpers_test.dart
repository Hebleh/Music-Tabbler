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
      'REVISION FROM: 09/07/2026',
      'My Chemical Romance',
    ]);

    expect(result.$1, 'Thank You for the Venom');
    expect(result.$2, 'My Chemical Romance');
  });
}
