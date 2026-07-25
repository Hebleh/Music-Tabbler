import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/semantic_recognition_service.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/domain/music_models.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  const service = SemanticRecognitionService();

  test('OCR geometry becomes editable unverified fret proposals', () {
    final result = service.propose(
      chartId: 'proposal',
      title: 'Synthetic',
      artist: 'Tester',
      strips: const [
        RecognitionStripInput(
          sourceId: 'self-authored-row',
          regions: [
            RecognizedTextRegion(
              text: '3',
              rect: NormalizedRect(0.1, 0.2, 0.13, 0.25),
            ),
            RecognizedTextRegion(
              text: '12',
              rect: NormalizedRect(0.4, 0.68, 0.45, 0.73),
            ),
            RecognizedTextRegion(
              text: 'word',
              rect: NormalizedRect(0.5, 0.9, 0.58, 0.95),
            ),
          ],
        ),
      ],
    );

    expect(result.proposedEvents, 2);
    expect(result.chart.measures, hasLength(1));
    expect(
      result.chart.measures.single.notes
          .map((note) => note.verification)
          .toSet(),
      {VerificationState.proposed},
    );
    expect(
      result.chart.measures.single.notes.every(
        (note) => note.confidence != null && note.sourceMapping != null,
      ),
      isTrue,
    );
    expect(result.chart.validationErrors(), isEmpty);
  });

  test('empty OCR row is retained with an explicit diagnostic', () {
    final result = service.propose(
      chartId: 'empty-proposal',
      title: 'Empty',
      artist: '',
      strips: const [RecognitionStripInput(sourceId: 'row', regions: [])],
    );
    expect(result.proposedEvents, 0);
    expect(result.chart.measures.single.notes, isEmpty);
    expect(result.diagnostics.single, contains('no fret digits'));
    expect(
      result.chart.measures.single.verification,
      VerificationState.proposed,
    );
  });
}
