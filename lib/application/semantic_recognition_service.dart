import '../domain/music_models.dart';
import '../domain/visual_chart_models.dart';
import 'service_contracts.dart';

class RecognitionStripInput {
  const RecognitionStripInput({
    required this.sourceId,
    required this.regions,
    this.stringCount = 5,
    this.tabBand = const NormalizedRect(0, 0.12, 1, 0.82),
  });

  final String sourceId;
  final List<RecognizedTextRegion> regions;
  final int stringCount;
  final NormalizedRect tabBand;
}

class SemanticRecognitionResult {
  const SemanticRecognitionResult({
    required this.chart,
    required this.diagnostics,
    required this.proposedEvents,
  });

  final SongChart chart;
  final List<String> diagnostics;
  final int proposedEvents;
}

/// Conservative local proposal engine over OCR geometry.
///
/// It never marks recognized material verified. One semantic measure is
/// proposed per already-cropped visual row, leaving the visual workflow as the
/// authoritative fallback while a musician corrects the proposal.
class SemanticRecognitionService {
  const SemanticRecognitionService();

  SemanticRecognitionResult propose({
    required String chartId,
    required String title,
    required String artist,
    required List<RecognitionStripInput> strips,
    BassTuning tuning = BassTuning.beadg,
  }) {
    if (strips.isEmpty) {
      throw const FormatException('Recognition needs at least one visual row.');
    }
    final measures = <ChartMeasure>[];
    final diagnostics = <String>[];
    var total = 0;
    for (final (measureIndex, strip) in strips.indexed) {
      if (strip.stringCount != tuning.strings.length) {
        diagnostics.add(
          'Row ${measureIndex + 1}: requested ${strip.stringCount} strings '
          'but the selected tuning has ${tuning.strings.length}.',
        );
      }
      final candidates = <_FretCandidate>[];
      for (final region in strip.regions) {
        final value = int.tryParse(region.text.trim());
        final centerY = (region.rect.top + region.rect.bottom) / 2;
        if (value == null ||
            value < 0 ||
            value > 36 ||
            centerY < strip.tabBand.top ||
            centerY > strip.tabBand.bottom) {
          continue;
        }
        final relativeY = (centerY - strip.tabBand.top) / strip.tabBand.height;
        final stringIndex = (relativeY * strip.stringCount).floor().clamp(
          0,
          strip.stringCount - 1,
        );
        candidates.add(
          _FretCandidate(
            fret: value,
            stringIndex: stringIndex,
            rect: region.rect,
          ),
        );
      }
      candidates.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      if (candidates.isEmpty) {
        diagnostics.add(
          'Row ${measureIndex + 1}: no fret digits were proposed.',
        );
      } else if (candidates.length > 16) {
        diagnostics.add(
          'Row ${measureIndex + 1}: only the first 16 fret candidates were '
          'placed; split or correct this row before verification.',
        );
      }
      final notes = <TabNote>[];
      for (final (ordinal, candidate) in candidates.take(16).indexed) {
        notes.add(
          TabNote.exact(
            id: 'proposal-${measureIndex + 1}-$ordinal',
            position: BeatFraction(ordinal % 16, 4),
            stringIndex: candidate.stringIndex.clamp(
              0,
              tuning.strings.length - 1,
            ),
            fret: candidate.fret,
            value: NoteValue.sixteenth,
            verification: VerificationState.proposed,
            confidence: _confidence(candidate, strip),
            sourceMapping: SourceMapping(
              sourceId: strip.sourceId,
              left: candidate.rect.left,
              top: candidate.rect.top,
              right: candidate.rect.right,
              bottom: candidate.rect.bottom,
            ),
          ),
        );
      }
      total += notes.length;
      measures.add(
        ChartMeasure.exact(
          number: measureIndex + 1,
          length: const TimeSignature(4, 4).quarterNoteLength,
          notes: List.unmodifiable(notes),
          verification: VerificationState.proposed,
          confidence: candidates.isEmpty
              ? 0
              : notes.map((note) => note.confidence!).reduce((a, b) => a + b) /
                    notes.length,
          sourceMapping: SourceMapping(
            sourceId: strip.sourceId,
            left: 0,
            top: strip.tabBand.top,
            right: 1,
            bottom: strip.tabBand.bottom,
          ),
        ),
      );
    }
    return SemanticRecognitionResult(
      chart: SongChart(
        id: chartId,
        title: title,
        artist: artist,
        tuning: tuning,
        measures: List.unmodifiable(measures),
        lyrics: const [],
      ),
      diagnostics: List.unmodifiable(diagnostics),
      proposedEvents: total,
    );
  }

  double _confidence(_FretCandidate candidate, RecognitionStripInput strip) {
    final centerY = (candidate.rect.top + candidate.rect.bottom) / 2;
    final relative = (centerY - strip.tabBand.top) / strip.tabBand.height;
    final ideal = (candidate.stringIndex + 0.5) / strip.stringCount;
    final offset = (relative - ideal).abs() * strip.stringCount;
    return (0.82 - offset * 0.28).clamp(0.35, 0.82);
  }
}

class _FretCandidate {
  const _FretCandidate({
    required this.fret,
    required this.stringIndex,
    required this.rect,
  });

  final int fret;
  final int stringIndex;
  final NormalizedRect rect;
}
