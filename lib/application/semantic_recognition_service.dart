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
    final lyrics = <LyricSyllable>[];
    final sections = <SongSection>[];
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
        final token = region.text.trim().toLowerCase();
        final value = token == 'x' ? 0 : int.tryParse(token);
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
      final likelyMeasureNumbers = _likelyMeasureNumberCandidates(candidates);
      if (likelyMeasureNumbers.isNotEmpty) {
        candidates.removeWhere(likelyMeasureNumbers.contains);
        diagnostics.add(
          'Row ${measureIndex + 1}: ignored '
          '${likelyMeasureNumbers.length} sequential measure-number '
          'candidate(s).',
        );
      }
      if (candidates.isEmpty) {
        diagnostics.add(
          'Row ${measureIndex + 1}: no fret digits or dead notes were proposed.',
        );
      } else if (candidates.length > 16) {
        diagnostics.add(
          'Row ${measureIndex + 1}: only the first 16 fret candidates were '
          'placed; split or correct this row before verification.',
        );
      }
      final notes = <TabNote>[];
      for (final (ordinal, candidate) in candidates.take(16).indexed) {
        final noteId = 'proposal-${measureIndex + 1}-$ordinal';
        final centerX = (candidate.rect.left + candidate.rect.right) / 2;
        final relativeX = centerX.clamp(0.0, 0.9999);
        notes.add(
          TabNote.exact(
            id: noteId,
            // Preserve the source row's horizontal geometry. The earlier
            // ordinal grid squeezed every 16-token row into adjacent labels
            // and made real OCR proposals appear as concatenated fret text.
            position: BeatFraction((relativeX * 4000).round(), 1000),
            stringIndex: candidate.stringIndex.clamp(
              0,
              tuning.strings.length - 1,
            ),
            fret: candidate.fret,
            value: _recognizedNoteValue(candidate, strip.regions),
            techniques: _recognizedTechniques(candidate, strip.regions),
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
      _recognizeSections(
        strip,
        measureIndex: measureIndex,
        destination: sections,
      );
      _recognizeLyrics(
        strip,
        measureIndex: measureIndex,
        notes: notes,
        destination: lyrics,
      );
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
        lyrics: List.unmodifiable(lyrics),
        sections: List.unmodifiable(sections),
      ),
      diagnostics: List.unmodifiable(diagnostics),
      proposedEvents: total,
    );
  }

  Set<_FretCandidate> _likelyMeasureNumberCandidates(
    List<_FretCandidate> candidates,
  ) {
    final rejected = <_FretCandidate>{};
    for (var start = 0; start < candidates.length; start += 1) {
      final first = candidates[start];
      // Keep ordinary consecutive fret phrases reviewable. Runs in the
      // measure-number range seen above real systems (20-36) are the narrow
      // legacy false-positive case this repair targets.
      if (first.fret < 20) continue;
      final run = <_FretCandidate>[first];
      for (var index = start + 1; index < candidates.length; index += 1) {
        final previous = run.last;
        final next = candidates[index];
        if (next.fret != previous.fret + 1 ||
            (_centerY(next) - _centerY(previous)).abs() > 0.025) {
          break;
        }
        run.add(next);
      }
      if (run.length >= 3) rejected.addAll(run);
    }
    return rejected;
  }

  double _centerY(_FretCandidate candidate) =>
      (candidate.rect.top + candidate.rect.bottom) / 2;

  double _confidence(_FretCandidate candidate, RecognitionStripInput strip) {
    final centerY = (candidate.rect.top + candidate.rect.bottom) / 2;
    final relative = (centerY - strip.tabBand.top) / strip.tabBand.height;
    final ideal = (candidate.stringIndex + 0.5) / strip.stringCount;
    final offset = (relative - ideal).abs() * strip.stringCount;
    return (0.82 - offset * 0.28).clamp(0.35, 0.82);
  }

  NoteValue _recognizedNoteValue(
    _FretCandidate candidate,
    List<RecognizedTextRegion> regions,
  ) {
    final marker = _nearbyMarker(candidate, regions, const {
      'w',
      'h',
      'q',
      'e',
      's',
      '16',
    });
    return switch (marker) {
      'w' => NoteValue.whole,
      'h' => NoteValue.half,
      'q' => NoteValue.quarter,
      'e' => NoteValue.eighth,
      's' || '16' => NoteValue.sixteenth,
      _ => NoteValue.sixteenth,
    };
  }

  List<TechniqueMark> _recognizedTechniques(
    _FretCandidate candidate,
    List<RecognizedTextRegion> regions,
  ) {
    final marker = _nearbyMarker(candidate, regions, const {
      '/',
      '\\',
      'b',
      'h',
      'p',
      'x',
      '<>',
      '~',
    });
    final kind = switch (marker) {
      '/' || '\\' => TechniqueKind.slide,
      'b' => TechniqueKind.bend,
      'h' => TechniqueKind.hammerOn,
      'p' => TechniqueKind.pullOff,
      'x' => TechniqueKind.deadNote,
      '<>' => TechniqueKind.naturalHarmonic,
      '~' => TechniqueKind.letRing,
      _ => null,
    };
    return kind == null ? const [] : [TechniqueMark(kind)];
  }

  String? _nearbyMarker(
    _FretCandidate candidate,
    List<RecognizedTextRegion> regions,
    Set<String> supported,
  ) {
    final centerX = (candidate.rect.left + candidate.rect.right) / 2;
    RecognizedTextRegion? nearest;
    var distance = 1.0;
    for (final region in regions) {
      final marker = region.text.trim().toLowerCase();
      if (!supported.contains(marker)) continue;
      final regionX = (region.rect.left + region.rect.right) / 2;
      final nextDistance = (regionX - centerX).abs();
      if (nextDistance < distance && nextDistance <= 0.035) {
        nearest = region;
        distance = nextDistance;
      }
    }
    return nearest?.text.trim().toLowerCase();
  }

  void _recognizeSections(
    RecognitionStripInput strip, {
    required int measureIndex,
    required List<SongSection> destination,
  }) {
    final pattern = RegExp(
      r'^(intro|verse|pre[\s-]?chorus|chorus|bridge|solo|outro)(\s+\d+)?$',
      caseSensitive: false,
    );
    for (final region in strip.regions) {
      final name = region.text.trim();
      if (pattern.hasMatch(name)) {
        destination.add(
          SongSection(
            id: 'proposal-section-$measureIndex-${destination.length}',
            name: name,
            measureIndex: measureIndex,
          ),
        );
      }
    }
  }

  void _recognizeLyrics(
    RecognitionStripInput strip, {
    required int measureIndex,
    required List<TabNote> notes,
    required List<LyricSyllable> destination,
  }) {
    final words = strip.regions.where((region) {
      final centerY = (region.rect.top + region.rect.bottom) / 2;
      final value = region.text.trim();
      return centerY > strip.tabBand.bottom &&
          value.isNotEmpty &&
          RegExp(r'[A-Za-z\u3040-\u30ff\u3400-\u9fff]').hasMatch(value);
    });
    for (final region in words) {
      final centerX = (region.rect.left + region.rect.right) / 2;
      TabNote? nearest;
      var distance = 2.0;
      for (final note in notes) {
        final mapping = note.sourceMapping!;
        final noteX = (mapping.left + mapping.right) / 2;
        final nextDistance = (noteX - centerX).abs();
        if (nextDistance < distance) {
          nearest = note;
          distance = nextDistance;
        }
      }
      destination.add(
        LyricSyllable.exact(
          id: 'proposal-lyric-$measureIndex-${destination.length}',
          measureIndex: measureIndex,
          position: nearest?.position ?? BeatFraction.zero,
          text: region.text.trim(),
          alignedNoteId: nearest?.id,
          verification: VerificationState.proposed,
          confidence: nearest == null ? 0.35 : 0.58,
          sourceMapping: SourceMapping(
            sourceId: strip.sourceId,
            left: region.rect.left,
            top: region.rect.top,
            right: region.rect.right,
            bottom: region.rect.bottom,
          ),
        ),
      );
    }
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
