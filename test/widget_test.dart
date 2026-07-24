import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/app.dart';
import 'package:music_tabbler/application/app_services.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/library_models.dart';
import 'package:music_tabbler/domain/device_preferences.dart';

void main() {
  testWidgets('opens the semantic sample chart from the song pool', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await _testServices();
    await tester.pumpWidget(MusicTabblerApp(services: services));
    await tester.pump();
    await tester.pump();

    expect(find.text('Song Pool'), findsWidgets);
    expect(find.text('Gigs'), findsOneWidget);
    expect(find.text('New / Import'), findsOneWidget);

    await tester.tap(find.text('Open sample chart'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Foundation Groove'), findsWidgets);
    expect(find.text('Tablature'), findsOneWidget);
    expect(find.text('Standard notation'), findsOneWidget);
    expect(find.text('Backing vocal mode'), findsOneWidget);
  });

  testWidgets('keeps tablature visible when notation is toggled off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await _testServices();
    await tester.pumpWidget(MusicTabblerApp(services: services));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Open sample chart'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Standard notation'));
    await tester.pump();

    final tabChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Tablature'),
    );
    final notationChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Standard notation'),
    );
    expect(tabChip.selected, isTrue);
    expect(notationChip.selected, isFalse);
  });

  testWidgets('Ctrl+V pastes a screenshot into the visual editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final importer = _RecordingImporter();

    await tester.pumpWidget(
      MusicTabblerApp(services: await _testServices(importer: importer)),
    );
    await tester.pump();
    await tester.tap(find.text('New visual chart'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(importer.pasteCalls, 1);
    expect(find.text('Row 1'), findsOneWidget);
  });

  testWidgets(
    'Android visual editor uses file pickers without desktop controls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MusicTabblerApp(services: await _testServices()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New / Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Add PNG / JPEG'), findsOneWidget);
      expect(find.text('Add PDF'), findsOneWidget);
      expect(find.textContaining('Paste image'), findsNothing);
      expect(
        find.textContaining('choose files stored on this device'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('direct URL creates an editable local provenance record', (
    tester,
  ) async {
    await tester.pumpWidget(MusicTabblerApp(services: await _testServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New / Import'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://www.songsterr.com/a/wsa/local-only-tab-s123',
    );
    await tester.tap(find.byTooltip('Create local source record'));
    await tester.pumpAndSettle();

    expect(find.text('Visual chart editor'), findsOneWidget);
    await tester.tap(find.byTooltip('Source details'));
    await tester.pumpAndSettle();
    expect(find.text('Songsterr'), findsOneWidget);
    expect(
      find.text('https://www.songsterr.com/a/wsa/local-only-tab-s123'),
      findsOneWidget,
    );
    expect(find.text('Music Tabbler never fetches the link.'), findsNothing);
  });

  testWidgets('mouse wheel can return upward after loading a long row list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final importer = _RecordingImporter(rowCount: 43);

    await tester.pumpWidget(
      MusicTabblerApp(services: await _testServices(importer: importer)),
    );
    await tester.pump();
    await tester.tap(find.text('New visual chart'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 500));

    const mouseDevice = 42;
    final mouse = await tester.createGesture(
      pointer: mouseDevice,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(640, 700));
    addTearDown(mouse.removePointer);
    for (var index = 0; index < 30; index += 1) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          device: mouseDevice,
          kind: PointerDeviceKind.mouse,
          position: const Offset(640, 700),
          scrollDelta: const Offset(0, 1200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Row 43'), findsOneWidget);

    for (var index = 0; index < 30; index += 1) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          device: mouseDevice,
          kind: PointerDeviceKind.mouse,
          position: const Offset(640, 700),
          scrollDelta: const Offset(0, -1200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Row 1'), findsOneWidget);
  });

  testWidgets('song pool falls back to artist and shows last edited metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = _FakeLibrary()
      ..drafts.add(
        VisualChartDraft(
          id: 'untitled',
          title: 'Untitled',
          artist: 'Hitorie',
          createdAt: DateTime.utc(2026, 7, 20, 12),
          updatedAt: DateTime.utc(2026, 7, 21, 12),
        ),
      );

    await tester.pumpWidget(
      MusicTabblerApp(services: await _testServices(library: library)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Hitorie'), findsOneWidget);
    expect(find.textContaining('Last edited'), findsOneWidget);
    expect(find.textContaining('Unknown artist'), findsNothing);
  });

  testWidgets(
    'setlist create validates, cancel preserves state, and CRUD works',
    (tester) async {
      final library = _FakeLibrary();
      await _pumpHome(tester, library);
      await _openGigs(tester);

      expect(find.text('No setlists yet'), findsOneWidget);
      await tester.tap(find.text('Create setlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a setlist name.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.setlists, isEmpty);

      await tester.tap(find.text('Create setlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'August gig');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('August gig'), findsOneWidget);

      await tester.tap(find.byTooltip('Setlist actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Practice set');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Practice set'), findsOneWidget);

      await tester.tap(find.byTooltip('Setlist actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Practice set'), findsOneWidget);

      await tester.tap(find.byTooltip('Setlist actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No setlists yet'), findsOneWidget);
    },
  );

  testWidgets('setlist supports duplicate songs and removing one occurrence', (
    tester,
  ) async {
    final library = _FakeLibrary()
      ..drafts.add(_draft('chart-a', 'Song A'))
      ..setlists.add(_setlist('set-1', 'Gig'));
    await _pumpHome(tester, library);
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 2; index += 1) {
      await tester.tap(find.text('Add song'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Song A'),
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(find.text('Song A'), findsNWidgets(2));
    expect(library.setlists.single.entries, hasLength(2));
    expect(
      library.setlists.single.entries.map((entry) => entry.id).toSet(),
      hasLength(2),
    );

    await tester.tap(find.byTooltip('Remove from setlist').first);
    await tester.pumpAndSettle();
    expect(find.text('Song A'), findsOneWidget);
    expect(library.setlists.single.entries, hasLength(1));
  });

  testWidgets('setlist drag handle reorders downward to the end', (
    tester,
  ) async {
    final library = _FakeLibrary()
      ..drafts.addAll([
        _draft('chart-a', 'Song A'),
        _draft('chart-b', 'Song B'),
        _draft('chart-c', 'Song C'),
      ])
      ..setlists.add(
        _setlist(
          'set-1',
          'Gig',
          entries: [
            const LibrarySetlistEntry(
              id: 'entry-a',
              chartVariantId: 'variant-chart-a',
            ),
            const LibrarySetlistEntry(
              id: 'entry-b',
              chartVariantId: 'variant-chart-b',
            ),
            const LibrarySetlistEntry(
              id: 'entry-c',
              chartVariantId: 'variant-chart-c',
            ),
          ],
        ),
      );
    await _pumpHome(tester, library);
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byTooltip('Drag to reorder').first,
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();

    expect(library.setlists.single.entries.map((entry) => entry.id), [
      'entry-b',
      'entry-c',
      'entry-a',
    ]);
  });

  testWidgets(
    'missing references stay visible and referenced chart deletion is explicit',
    (tester) async {
      final library = _FakeLibrary()
        ..drafts.add(_draft('chart-a', 'Song A'))
        ..setlists.add(
          _setlist(
            'set-1',
            'Gig',
            entries: const [
              LibrarySetlistEntry(
                id: 'entry-a',
                chartVariantId: 'variant-chart-a',
              ),
              LibrarySetlistEntry(id: 'missing', chartVariantId: 'gone'),
            ],
          ),
        );
      await _pumpHome(tester, library);
      await _openGigs(tester);
      await tester.tap(find.text('Gig'));
      await tester.pumpAndSettle();
      expect(find.text('Missing chart'), findsOneWidget);
      expect(
        find.textContaining('Referenced chart is unavailable'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song Pool'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete saved chart'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Chart is used in setlists'), findsOneWidget);
      await tester.tap(find.text('Keep chart'));
      await tester.pumpAndSettle();
      expect(library.drafts, hasLength(1));

      await tester.tap(find.byTooltip('Delete saved chart'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove and delete'));
      await tester.pumpAndSettle();
      expect(library.drafts, isEmpty);
      expect(library.setlists.single.entries, hasLength(1));
      expect(library.setlists.single.entries.single.id, 'missing');

      await tester.tap(find.text('Gigs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gig'));
      await tester.pumpAndSettle();
      expect(find.text('Missing chart'), findsOneWidget);
      expect(find.text('Song A'), findsNothing);
    },
  );

  testWidgets('placeholders are editable, red, removable, and reorderable', (
    tester,
  ) async {
    final library = _FakeLibrary()
      ..drafts.add(_draft('chart-a', 'Song A'))
      ..setlists.add(
        _setlist(
          'set-1',
          'Gig',
          entries: const [
            LibrarySetlistEntry(
              id: 'entry-a',
              chartVariantId: 'variant-chart-a',
            ),
          ],
        ),
      );
    await _pumpHome(tester, library);
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add placeholder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a placeholder name.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).last,
      'Singer feature song',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Singer feature song'), findsOneWidget);
    expect(find.text('Not playing'), findsOneWidget);
    final placeholderCard = tester.widget<Card>(
      find.ancestor(
        of: find.text('Singer feature song'),
        matching: find.byType(Card),
      ),
    );
    expect(placeholderCard.color, Colors.red.shade100);

    await tester.tap(find.byTooltip('Edit placeholder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Singer encore');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Singer encore'), findsOneWidget);
    expect(
      library.setlists.single.entries.last.placeholderTitle,
      'Singer encore',
    );

    await tester.drag(
      find.byTooltip('Drag to reorder').last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(
      library.setlists.single.entries.first.kind,
      SetlistEntryKind.placeholder,
    );

    await tester.tap(find.byTooltip('Remove from setlist').first);
    await tester.pumpAndSettle();
    expect(find.text('Singer encore'), findsNothing);
    expect(library.setlists.single.entries.single.id, 'entry-a');
  });

  testWidgets('setlist export sends the selected density and reports success', (
    tester,
  ) async {
    final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
    final exporter = _RecordingSetlistExporter();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MusicTabblerApp(
        services: await _testServices(
          library: library,
          setlistExporter: exporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export setlist A4 PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage readable'));
    await tester.pumpAndSettle();

    expect(exporter.exportedSetlist?.id, 'set-1');
    expect(exporter.density, VisualExportDensity.stageReadable);
    expect(find.textContaining('Exported setlist PDF'), findsOneWidget);
  });

  testWidgets('performance preview navigates and exits explicitly', (
    tester,
  ) async {
    final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
    final deckBuilder = _RecordingPerformanceDeckBuilder();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MusicTabblerApp(
        services: await _testServices(
          library: library,
          performanceDeckBuilder: deckBuilder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open performance preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage readable'));
    await tester.pumpAndSettle();

    expect(deckBuilder.density, VisualExportDensity.stageReadable);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Not playing - First break'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Not playing - Second break'), findsOneWidget);
    await tester.tap(find.byTooltip('Exit performance preview'));
    await tester.pumpAndSettle();
    expect(find.text('Gig'), findsWidgets);
  });

  testWidgets('gig mode swipes safely and releases performance mode on exit', (
    tester,
  ) async {
    final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
    final deckBuilder = _RecordingPerformanceDeckBuilder();
    final performanceMode = _RecordingPerformanceModeController();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MusicTabblerApp(
        services: await _testServices(
          library: library,
          performanceDeckBuilder: deckBuilder,
          performanceMode: performanceMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Start gig mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage readable'));
    await tester.pumpAndSettle();

    expect(performanceMode.values, contains(true));
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Use Exit to leave gig mode safely.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(performanceMode.values.last, isFalse);
    expect(find.text('Gig'), findsWidgets);
  });

  testWidgets('setlist cards and actions fit a narrow tablet layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = _FakeLibrary()
      ..setlists.add(
        _setlist(
          'set-1',
          'Gig',
          entries: const [
            LibrarySetlistEntry.placeholder(
              id: 'placeholder',
              title: 'Singer feature',
            ),
          ],
        ),
      );
    await tester.pumpWidget(
      MusicTabblerApp(services: await _testServices(library: library)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gigs'));
    await tester.pumpAndSettle();

    expect(find.text('Gig'), findsOneWidget);
    expect(find.byTooltip('Setlist actions'), findsOneWidget);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();
    expect(find.text('Singer feature'), findsOneWidget);
    expect(find.text('Add song'), findsOneWidget);
    expect(find.text('Add placeholder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHome(WidgetTester tester, _FakeLibrary library) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MusicTabblerApp(services: await _testServices(library: library)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openGigs(WidgetTester tester) async {
  await tester.tap(find.text('Gigs'));
  await tester.pumpAndSettle();
}

VisualChartDraft _draft(String id, String title) => VisualChartDraft(
  id: id,
  title: title,
  artist: 'Artist',
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
);

LibrarySetlist _setlist(
  String id,
  String name, {
  List<LibrarySetlistEntry> entries = const [],
}) => LibrarySetlist(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
  entries: entries,
);

Future<AppServices> _testServices({
  VisualImporter? importer,
  _FakeLibrary? library,
  SetlistPdfExporter? setlistExporter,
  PerformanceDeckBuilder? performanceDeckBuilder,
  PerformanceModeController? performanceMode,
}) async {
  final resolvedLibrary = library ?? _FakeLibrary();
  const unusedExporter = _UnusedExporter();
  return AppServices(
    library: resolvedLibrary,
    songVariants: resolvedLibrary,
    setlists: resolvedLibrary,
    importer: importer ?? const _UnusedImporter(),
    exporter: unusedExporter,
    setlistExporter: setlistExporter ?? unusedExporter,
    performanceDeckBuilder: performanceDeckBuilder ?? unusedExporter,
    textRecognition: const _UnusedTextRecognition(),
    preferences: _MemoryPreferencesStore(),
    performanceMode: performanceMode ?? _RecordingPerformanceModeController(),
  );
}

class _MemoryPreferencesStore implements DevicePreferencesStore {
  DevicePreferences value = DevicePreferences.defaults;

  @override
  Future<DevicePreferences> load() async => value;

  @override
  Future<void> save(DevicePreferences preferences) async {
    value = preferences;
  }
}

class _RecordingPerformanceModeController implements PerformanceModeController {
  final values = <bool>[];

  @override
  Future<void> setActive(bool active) async {
    values.add(active);
  }
}

class _RecordingImporter implements VisualImporter {
  _RecordingImporter({this.rowCount = 1});

  final int rowCount;
  int pasteCalls = 0;

  @override
  Future<List<VisualStrip>> pasteImages() async {
    pasteCalls += 1;
    return [
      for (var index = 0; index < rowCount; index += 1)
        VisualStrip(
          id: 'pasted-$index',
          assetHash: 'asset',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 50,
        ),
    ];
  }

  @override
  Future<List<VisualStrip>> importPaths(Iterable<String> paths) async => [];

  @override
  Future<List<VisualStrip>> pickImages() async => [];

  @override
  Future<List<VisualStrip>> pickPdf() async => [];
}

class _FakeLibrary implements ChartLibrary, SongVariantLibrary, SetlistLibrary {
  final List<VisualChartDraft> drafts = [];
  final List<LibrarySetlist> setlists = [];

  @override
  String assetPath(String hash, String extension) => '';

  @override
  Future<void> deleteDraft(String id) async {
    final variantId = 'variant-$id';
    final references = [
      for (final setlist in setlists)
        if (setlist.entries.any((entry) => entry.chartVariantId == variantId))
          setlist.id,
    ];
    if (references.isNotEmpty) {
      throw ChartVariantReferencedBySetlistsException(
        chartVariantId: variantId,
        setlistIds: references,
      );
    }
    drafts.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> deleteDraftAndRemoveSetlistReferences(
    String id, {
    required DateTime updatedAt,
  }) async {
    final variantId = 'variant-$id';
    for (var index = 0; index < setlists.length; index += 1) {
      final setlist = setlists[index];
      final retained = setlist.entries
          .where((entry) => entry.chartVariantId != variantId)
          .toList(growable: false);
      if (retained.length == setlist.entries.length) continue;
      setlists[index] = LibrarySetlist(
        id: setlist.id,
        name: setlist.name,
        createdAt: setlist.createdAt,
        updatedAt: updatedAt,
        scheduledAt: setlist.scheduledAt,
        notes: setlist.notes,
        entries: retained,
      );
    }
    drafts.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<VisualChartDraft>> listDrafts() async => List.of(drafts);

  @override
  Future<VisualChartDraft?> loadDraft(String id) async {
    for (final draft in drafts) {
      if (draft.id == id) return draft;
    }
    return null;
  }

  @override
  Future<void> saveDraft(VisualChartDraft draft) async {
    drafts.removeWhere((item) => item.id == draft.id);
    drafts.add(draft);
  }

  @override
  Future<ChartVariantIdentity?> identityForDraft(String draftId) async {
    final draft = await loadDraft(draftId);
    if (draft == null) return null;
    return ChartVariantIdentity(
      id: 'variant-$draftId',
      songId: 'song-$draftId',
      kind: ChartVariantKind.visual,
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
    );
  }

  @override
  Future<List<LibrarySong>> listSongs() async => [];

  @override
  Future<List<ChartVariantIdentity>> listVariants(String songId) async => [];

  @override
  Future<void> saveDraftAsVariant(
    VisualChartDraft draft, {
    required String songId,
  }) => saveDraft(draft);

  @override
  Future<void> saveSetlist(LibrarySetlist setlist) async {
    setlists.removeWhere((item) => item.id == setlist.id);
    setlists.add(setlist);
  }

  @override
  Future<List<LibrarySetlist>> listSetlists() async => List.of(setlists);

  @override
  Future<LibrarySetlist?> loadSetlist(String id) async {
    for (final setlist in setlists) {
      if (setlist.id == id) return setlist;
    }
    return null;
  }

  @override
  Future<void> reorderSetlistEntries(
    String setlistId,
    List<String> orderedEntryIds, {
    required DateTime updatedAt,
  }) async {
    final current = await loadSetlist(setlistId);
    if (current == null) return;
    final byId = {for (final entry in current.entries) entry.id: entry};
    await saveSetlist(
      LibrarySetlist(
        id: current.id,
        name: current.name,
        createdAt: current.createdAt,
        updatedAt: updatedAt,
        scheduledAt: current.scheduledAt,
        notes: current.notes,
        entries: [for (final id in orderedEntryIds) byId[id]!],
      ),
    );
  }

  @override
  Future<void> deleteSetlist(String id) async {
    setlists.removeWhere((item) => item.id == id);
  }
}

class _UnusedImporter implements VisualImporter {
  const _UnusedImporter();
  @override
  Future<List<VisualStrip>> pickImages() => throw UnimplementedError();
  @override
  Future<List<VisualStrip>> pickPdf() => throw UnimplementedError();
  @override
  Future<List<VisualStrip>> pasteImages() => throw UnimplementedError();
  @override
  Future<List<VisualStrip>> importPaths(Iterable<String> paths) =>
      throw UnimplementedError();
}

class _UnusedTextRecognition implements TextRecognitionService {
  const _UnusedTextRecognition();

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      const MetadataSuggestion();
}

class _UnusedExporter
    implements ChartPdfExporter, SetlistPdfExporter, PerformanceDeckBuilder {
  const _UnusedExporter();
  @override
  Future<Uint8List> exportBytes(VisualChartDraft draft) =>
      throw UnimplementedError();
  @override
  Future<String?> exportWithPicker(VisualChartDraft draft) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> exportSetlistBytes(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) => throw UnimplementedError();

  @override
  Future<String?> exportSetlistWithPicker(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) => throw UnimplementedError();

  @override
  Future<PerformanceDeck> buildPerformanceDeck(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) => throw UnimplementedError();
}

class _RecordingSetlistExporter implements SetlistPdfExporter {
  LibrarySetlist? exportedSetlist;
  VisualExportDensity? density;

  @override
  Future<Uint8List> exportSetlistBytes(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async {
    exportedSetlist = setlist;
    this.density = density;
    return Uint8List.fromList([1]);
  }

  @override
  Future<String?> exportSetlistWithPicker(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async {
    exportedSetlist = setlist;
    this.density = density;
    return r'C:\exports\Gig.pdf';
  }
}

class _RecordingPerformanceDeckBuilder implements PerformanceDeckBuilder {
  VisualExportDensity? density;

  @override
  Future<PerformanceDeck> buildPerformanceDeck(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async {
    this.density = density;
    PerformanceDeckPage page(int index, String title) => PerformanceDeckPage(
      id: '${setlist.id}:${density.name}:$index',
      index: index,
      elements: [
        PerformanceDeckElement(
          kind: PerformanceElementKind.placeholder,
          entryIndex: index,
          entryId: 'entry-$index',
          title: title,
          width: 831.89,
          height: 22,
        ),
      ],
    );
    return PerformanceDeck(
      setlistId: setlist.id,
      setlistName: setlist.name,
      density: density,
      pageWidth: 841.89,
      pageHeight: 595.28,
      margin: 5,
      gap: 0,
      pages: [page(0, 'First break'), page(1, 'Second break')],
    );
  }
}
