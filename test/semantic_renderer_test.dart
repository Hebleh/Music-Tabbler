import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/semantic_layout.dart';
import 'package:music_tabbler/application/semantic_pdf_export_service.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  test('title visibility does not reflow semantic music positions', () {
    const engine = SemanticLayoutEngine();
    final chart = SongChart.foundationExample();

    final withTitle = engine.build(
      chart,
      showTitle: true,
      showTab: true,
      showNotation: true,
    );
    final withoutTitle = engine.build(
      chart,
      showTitle: false,
      showTab: true,
      showNotation: true,
    );

    expect(
      withTitle.noteTargets.map(
        (target) => (target.noteId, target.x, target.y),
      ),
      withoutTitle.noteTargets.map(
        (target) => (target.noteId, target.x, target.y),
      ),
    );
    expect(
      withoutTitle.primitives.whereType<SemanticTextPrimitive>().any(
        (text) => text.role == SemanticTextRole.title,
      ),
      isFalse,
    );
  });

  test('tablature and notation primitives toggle independently', () {
    const engine = SemanticLayoutEngine();
    final chart = SongChart.foundationExample();

    final tabOnly = engine.build(
      chart,
      showTitle: false,
      showTab: true,
      showNotation: false,
    );
    final notationOnly = engine.build(
      chart,
      showTitle: false,
      showTab: false,
      showNotation: true,
    );

    expect(tabOnly.primitives.whereType<SemanticEllipsePrimitive>(), isEmpty);
    expect(tabOnly.noteTargets, isNotEmpty);
    expect(
      notationOnly.primitives.whereType<SemanticEllipsePrimitive>(),
      isNotEmpty,
    );
    expect(notationOnly.noteTargets, isEmpty);
  });

  test(
    'semantic A4 export uses the shared plan and paginates systems',
    () async {
      final base = SongChart.foundationExample();
      final measures = <ChartMeasure>[];
      for (var index = 0; index < 24; index += 1) {
        final source = base.measures[index % base.measures.length];
        measures.add(
          ChartMeasure.exact(
            number: index + 1,
            length: source.length,
            timeSignature: source.timeSignature,
            notes: source.notes,
          ),
        );
      }
      final chart = base.copyWith(
        id: 'long-semantic',
        title: 'Long semantic chart',
        measures: measures,
        lyrics: const [],
      );

      final bytes = await const SemanticPdfExportService().exportSemanticBytes(
        chart,
        showTitle: true,
        showTab: true,
        showNotation: true,
      );
      final source = latin1.decode(bytes, allowInvalid: true);

      expect(source, contains('/MediaBox[0 0 595.27559 841.88976]'));
      expect(RegExp(r'/Type/Page\b').allMatches(source).length, 2);
    },
  );
}
