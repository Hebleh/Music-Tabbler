import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/music_xml_service.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  const service = MusicXmlService();

  test('supported MusicXML subset round-trips semantically', () {
    final source = SongChart.foundationExample().copyWith(
      sections: const [
        SongSection(id: 'verse', name: 'Verse', measureIndex: 0),
      ],
      repeats: const [
        RepeatRegion(
          id: 'repeat',
          startMeasureIndex: 0,
          endMeasureIndex: 1,
          times: 3,
        ),
      ],
    );

    final exported = service.exportChart(source);
    final imported = service.importChart(exported.xml);

    expect(exported.diagnostics, isEmpty);
    expect(imported.chart.title, source.title);
    expect(imported.chart.artist, source.artist);
    expect(
      imported.chart.tuning.strings.map((value) => value.midiPitch),
      source.tuning.strings.map((value) => value.midiPitch),
    );
    expect(imported.chart.measures, hasLength(source.measures.length));
    expect(
      imported.chart.measures.first.notes.first.fret,
      source.measures.first.notes.first.fret,
    );
    expect(
      imported.chart.measures.first.notes.first.position,
      source.measures.first.notes.first.position,
    );
    expect(imported.chart.lyrics.first.text, source.lyrics.first.text);
    expect(imported.chart.sections.single.name, 'Verse');
    expect(imported.chart.repeats.single.times, 3);
  });

  test('malformed and unsupported MusicXML fail or diagnose explicitly', () {
    expect(
      () => service.importChart('<score-timewise/>'),
      throwsA(isA<FormatException>()),
    );

    const twoParts = '''
<score-partwise version="4.0">
  <part-list>
    <score-part id="P1"><part-name>Bass</part-name></score-part>
    <score-part id="P2"><part-name>Other</part-name></score-part>
  </part-list>
  <part id="P1"><measure number="1"><attributes><divisions>1</divisions>
    <time><beats>4</beats><beat-type>4</beat-type></time></attributes>
    <note><rest/><duration>4</duration><type>whole</type></note>
  </measure></part>
  <part id="P2"><measure number="1"/></part>
</score-partwise>
''';
    final imported = service.importChart(twoParts);
    expect(imported.diagnostics.any((item) => item.isLoss), isTrue);
    expect(
      imported.diagnostics.map((item) => item.message),
      contains('Only the first MusicXML part was imported.'),
    );
  });
}
