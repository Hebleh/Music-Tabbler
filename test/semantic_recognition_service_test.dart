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

  test('rhythm markers techniques sections and lyrics stay proposed', () {
    final result = service.propose(
      chartId: 'musical-proposal',
      title: 'Synthetic',
      artist: '',
      strips: const [
        RecognitionStripInput(
          sourceId: 'row',
          regions: [
            RecognizedTextRegion(
              text: 'Verse 1',
              rect: NormalizedRect(0.02, 0.01, 0.14, 0.06),
            ),
            RecognizedTextRegion(
              text: '3',
              rect: NormalizedRect(0.2, 0.2, 0.23, 0.25),
            ),
            RecognizedTextRegion(
              text: '/',
              rect: NormalizedRect(0.225, 0.22, 0.24, 0.27),
            ),
            RecognizedTextRegion(
              text: 'e',
              rect: NormalizedRect(0.19, 0.14, 0.21, 0.17),
            ),
            RecognizedTextRegion(
              text: 'hello',
              rect: NormalizedRect(0.18, 0.88, 0.27, 0.94),
            ),
          ],
        ),
      ],
    );

    final note = result.chart.measures.single.notes.single;
    expect(note.value, NoteValue.eighth);
    expect(note.techniques.single.kind, TechniqueKind.slide);
    expect(result.chart.sections.single.name, 'Verse 1');
    expect(result.chart.lyrics.single.text, 'hello');
    expect(result.chart.lyrics.single.verification, VerificationState.proposed);
  });

  test('standalone X tokens become proposed dead notes', () {
    final result = service.propose(
      chartId: 'dead-note-proposal',
      title: 'Synthetic',
      artist: '',
      strips: const [
        RecognitionStripInput(
          sourceId: 'row',
          stringCount: 4,
          tabBand: NormalizedRect(0, 0.5, 1, 0.99),
          regions: [
            RecognizedTextRegion(
              text: 'X',
              rect: NormalizedRect(0.3, 0.61, 0.33, 0.66),
            ),
          ],
        ),
      ],
      tuning: BassTuning.eadg,
    );

    final note = result.chart.measures.single.notes.single;
    expect(note.fret, 0);
    expect(note.techniques.single.kind, TechniqueKind.deadNote);
    expect(note.verification, VerificationState.proposed);
  });

  test('proposal beat positions preserve source horizontal spacing', () {
    final result = service.propose(
      chartId: 'spaced-proposal',
      title: 'Synthetic',
      artist: '',
      strips: const [
        RecognitionStripInput(
          sourceId: 'row',
          regions: [
            RecognizedTextRegion(
              text: '11',
              rect: NormalizedRect(0.10, 0.2, 0.13, 0.25),
            ),
            RecognizedTextRegion(
              text: '12',
              rect: NormalizedRect(0.80, 0.2, 0.83, 0.25),
            ),
          ],
        ),
      ],
    );

    final notes = result.chart.measures.single.notes;
    expect(notes[0].position.value, closeTo(0.46, 0.01));
    expect(notes[1].position.value, closeTo(3.26, 0.01));
  });

  test('sequential measure labels are not proposed as frets', () {
    final result = service.propose(
      chartId: 'measure-labels',
      title: 'Synthetic',
      artist: '',
      strips: const [
        RecognitionStripInput(
          sourceId: 'row',
          regions: [
            RecognizedTextRegion(
              text: '31',
              rect: NormalizedRect(0.10, 0.20, 0.13, 0.24),
            ),
            RecognizedTextRegion(
              text: '32',
              rect: NormalizedRect(0.25, 0.20, 0.28, 0.24),
            ),
            RecognizedTextRegion(
              text: '33',
              rect: NormalizedRect(0.40, 0.20, 0.43, 0.24),
            ),
            RecognizedTextRegion(
              text: '34',
              rect: NormalizedRect(0.55, 0.20, 0.58, 0.24),
            ),
            RecognizedTextRegion(
              text: '7',
              rect: NormalizedRect(0.72, 0.50, 0.75, 0.55),
            ),
          ],
        ),
      ],
    );

    expect(result.chart.measures.single.notes, hasLength(1));
    expect(result.chart.measures.single.notes.single.fret, 7);
    expect(
      result.diagnostics,
      contains('Row 1: ignored 4 sequential measure-number candidate(s).'),
    );
  });

  test('non-sequential high frets remain reviewable proposals', () {
    final result = service.propose(
      chartId: 'high-frets',
      title: 'Synthetic',
      artist: '',
      strips: const [
        RecognitionStripInput(
          sourceId: 'row',
          regions: [
            RecognizedTextRegion(
              text: '12',
              rect: NormalizedRect(0.10, 0.20, 0.13, 0.24),
            ),
            RecognizedTextRegion(
              text: '15',
              rect: NormalizedRect(0.25, 0.20, 0.28, 0.24),
            ),
            RecognizedTextRegion(
              text: '17',
              rect: NormalizedRect(0.40, 0.20, 0.43, 0.24),
            ),
          ],
        ),
      ],
    );

    expect(result.chart.measures.single.notes.map((note) => note.fret), [
      12,
      15,
      17,
    ]);
  });

  test('ordinary consecutive frets remain reviewable proposals', () {
    final result = service.propose(
      chartId: 'consecutive-frets',
      title: 'Synthetic',
      artist: '',
      strips: const [
        RecognitionStripInput(
          sourceId: 'row',
          regions: [
            RecognizedTextRegion(
              text: '12',
              rect: NormalizedRect(0.10, 0.50, 0.13, 0.54),
            ),
            RecognizedTextRegion(
              text: '13',
              rect: NormalizedRect(0.25, 0.50, 0.28, 0.54),
            ),
            RecognizedTextRegion(
              text: '14',
              rect: NormalizedRect(0.40, 0.50, 0.43, 0.54),
            ),
          ],
        ),
      ],
    );

    expect(result.chart.measures.single.notes.map((note) => note.fret), [
      12,
      13,
      14,
    ]);
  });

  test('reviewed long rows retain more than sixteen selectable proposals', () {
    final result = service.propose(
      chartId: 'reviewed-long-row',
      title: 'Synthetic',
      artist: '',
      strips: [
        RecognitionStripInput(
          sourceId: 'row',
          regions: const [],
          reviewedFretCandidates: [
            for (var index = 0; index < 24; index += 1)
              ReviewedFretCandidateInput(
                fret: index % 12,
                stringIndex: index % 4,
                rect: NormalizedRect(
                  index / 25,
                  0.2 + (index % 4) * 0.1,
                  (index + 0.5) / 25,
                  0.24 + (index % 4) * 0.1,
                ),
                sourceRect: NormalizedRect(
                  0.1 + index / 30,
                  0.3,
                  0.11 + index / 30,
                  0.34,
                ),
                confidence: 0.9,
              ),
          ],
          stringCount: 4,
        ),
      ],
      tuning: BassTuning.eadg,
    );

    expect(result.proposedEvents, 24);
    expect(result.chart.measures.single.notes, hasLength(24));
    expect(result.chart.measures.single.notes.first.stringIndex, 0);
    expect(result.chart.measures.single.notes[3].stringIndex, 3);
    expect(
      result.chart.measures.single.notes.first.sourceMapping!.left,
      closeTo(0.1, 0.001),
    );
  });
}
