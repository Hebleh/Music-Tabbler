import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/app.dart';
import 'package:music_tabbler/application/app_services.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/application/visual_tab_analysis_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/library_models.dart';
import 'package:music_tabbler/domain/device_preferences.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/features/import/visual_tab_analysis_dialog.dart';

void main() {
  testWidgets(
    'visual tab analysis review is a keyboard-dismissible page route',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final services = await _testServices();
      List<VisualTabAnalysis>? outcome;
      var returned = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  outcome = await showVisualTabAnalysisReview(
                    context: context,
                    library: services.library,
                    analyzer: VisualTabAnalysisService(
                      library: services.library,
                      textRecognition: services.textRecognition,
                    ),
                    strips: const [],
                    sourceStringCount: 4,
                  );
                  returned = true;
                },
                child: const Text('Open review'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open review'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Review visual tab analysis'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.text('Use reviewed analysis'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(returned, isTrue);
      expect(outcome, isEmpty);

      returned = false;
      outcome = null;
      await tester.tap(find.text('Open review'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(returned, isTrue);
      expect(outcome, isNull);
      expect(find.text('Review visual tab analysis'), findsNothing);

      returned = false;
      await tester.tap(find.text('Open review'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 800));

      expect(returned, isTrue);
      expect(outcome, isNull);
      expect(find.text('Review visual tab analysis'), findsNothing);
    },
  );

  testWidgets('visual tab review can rerun every row through raster OCR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = _FakeLibrary();
    final analyzer = _RecordingVisualTabAnalyzer(library);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showVisualTabAnalysisReview(
                context: context,
                library: library,
                analyzer: analyzer,
                strips: const [
                  VisualStrip(
                    id: 'row-a',
                    assetHash: 'a',
                    assetExtension: 'png',
                    pixelWidth: 400,
                    pixelHeight: 100,
                  ),
                  VisualStrip(
                    id: 'row-b',
                    assetHash: 'b',
                    assetExtension: 'png',
                    pixelWidth: 400,
                    pixelHeight: 100,
                  ),
                ],
                sourceStringCount: 4,
              ),
              child: const Text('Open review'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open review'));
    for (var index = 0; index < 5; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(analyzer.preferPositionedPdf, [isTrue, isTrue]);

    await tester.tap(find.byKey(const ValueKey('raster-ocr-all-rows')));
    for (var index = 0; index < 5; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(analyzer.preferPositionedPdf, [isTrue, isTrue, isFalse, isFalse]);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('visual tab review matches seam risks to numbered markers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = _FakeLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showVisualTabAnalysisReview(
                context: context,
                library: library,
                analyzer: _SeamRiskVisualTabAnalyzer(library),
                strips: const [
                  VisualStrip(
                    id: 'risk-row',
                    assetHash: 'risk',
                    assetExtension: 'png',
                    pixelWidth: 400,
                    pixelHeight: 100,
                  ),
                ],
                sourceStringCount: 4,
              ),
              child: const Text('Open review'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open review'));
    for (var index = 0; index < 4; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Find the matching red numbered marker.'), findsOneWidget);
    expect(
      find.text('Its dashed line shows the seam between two strings.'),
      findsOneWidget,
    );
    expect(find.text('Marker 1 · between strings 2 and 3'), findsOneWidget);
    expect(find.byTooltip('Remove seam marker'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Remove seam marker').first);
    await tester.pump();
    expect(find.text('Marker 1 · between strings 2 and 3'), findsOneWidget);
    expect(find.byTooltip('Remove seam marker'), findsOneWidget);
    expect(find.text('Marker 2 · between strings 2 and 3'), findsNothing);
  });

  testWidgets(
    'visual tab review can explicitly preserve a tokenless row unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final library = _FakeLibrary();
      final analyzer = _BlockedVisualTabAnalyzer(library);
      List<VisualTabAnalysis>? outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  outcome = await showVisualTabAnalysisReview(
                    context: context,
                    library: library,
                    analyzer: analyzer,
                    strips: const [
                      VisualStrip(
                        id: 'ready-row',
                        assetHash: 'a',
                        assetExtension: 'png',
                        pixelWidth: 400,
                        pixelHeight: 100,
                      ),
                      VisualStrip(
                        id: 'blocked-row',
                        assetHash: 'b',
                        assetExtension: 'png',
                        pixelWidth: 400,
                        pixelHeight: 100,
                      ),
                    ],
                    sourceStringCount: 4,
                  );
                },
                child: const Text('Open review'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open review'));
      for (var index = 0; index < 6; index += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Continue (1 unchanged)'), findsOneWidget);

      await tester.tap(find.text('Continue (1 unchanged)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Row 2 has no usable fret tokens'), findsOneWidget);
      await tester.tap(find.text('Keep unchanged and continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(outcome, isNotNull);
      expect(outcome, hasLength(2));
      expect(outcome!.first.keepUnchanged, isFalse);
      expect(outcome!.last.keepUnchanged, isTrue);
    },
  );

  testWidgets('semantic workflows are absent from the visual-first UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
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

    expect(find.text('Foundation Groove'), findsNothing);
    expect(find.textContaining('semantic', findRichText: true), findsNothing);
    expect(find.text('New visual chart'), findsOneWidget);
  });

  testWidgets('Song Pool fits a portrait iPhone viewport', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MusicTabblerApp(services: await _testServices()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Song Pool'), findsWidgets);
    expect(find.text('New visual chart'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.byKey(const ValueKey('detect-all-rows')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('detect-all-rows')))
          .onPressed,
      isNotNull,
    );
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
    expect(
      find.text('The link is saved as source information only.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not download or scrape Songsterr'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Source details'));
    await tester.pumpAndSettle();
    expect(find.text('Songsterr'), findsOneWidget);
    expect(
      find.text('https://www.songsterr.com/a/wsa/local-only-tab-s123'),
      findsOneWidget,
    );
    expect(find.text('Music Tabbler never fetches the link.'), findsNothing);
  });

  testWidgets('new import exposes only the visual recognition workflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MusicTabblerApp(services: await _testServices()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New / Import'));
    await tester.pumpAndSettle();

    expect(find.textContaining('semantic'), findsNothing);
    await tester.ensureVisible(find.text('Visual chart workflow'));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Visual chart editor'), findsOneWidget);
    expect(find.byTooltip('Recognize semantic proposal'), findsNothing);
  });

  testWidgets('an Android-shared PDF opens in the visual editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final importer = _RecordingImporter();
    final receiver = _PendingPdfReceiver(
      IncomingPdf(bytes: Uint8List.fromList([1, 2, 3]), fileName: 'Set.pdf'),
    );

    await tester.pumpWidget(
      MusicTabblerApp(
        services: await _testServices(
          importer: importer,
          incomingPdf: receiver,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Visual chart editor'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Set'), findsOneWidget);
    expect(importer.sharedPdfCalls, 1);
  });

  testWidgets('library transfer exposes export merge replace and restore', (
    tester,
  ) async {
    await tester.pumpWidget(
      MusicTabblerApp(
        services: await _testServices(
          libraryState: _RecordingLibraryStateTransfer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Library transfer and recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Export .mtstate'), findsOneWidget);
    expect(find.text('Import and keep local library'), findsOneWidget);
    expect(find.text('Replace from .mtstate'), findsOneWidget);
    expect(find.text('Restore a backup'), findsOneWidget);
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

  testWidgets('setlist editor leaves theme selection to gig mode', (
    tester,
  ) async {
    final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
    final preferences = _MemoryPreferencesStore();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MusicTabblerApp(
        services: await _testServices(
          library: library,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Use light theme'), findsNothing);
    expect(find.byTooltip('Use dark theme'), findsNothing);
    expect(preferences.value.appTheme, AppThemePreference.dark);
  });

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
    expect(find.text('Setlist PDF density'), findsOneWidget);
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
    expect(find.text('Performance preview density'), findsOneWidget);
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
    final preferences = _MemoryPreferencesStore();
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
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openGigs(tester);
    await tester.tap(find.text('Gig'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Start gig mode'));
    await tester.pumpAndSettle();
    expect(find.text('Gig display density'), findsOneWidget);
    await tester.tap(find.text('Stage readable'));
    await tester.pumpAndSettle();

    expect(performanceMode.values, contains(true));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byTooltip('Open setlist sidebar'), findsOneWidget);
    expect(find.byTooltip('Draw annotations'), findsOneWidget);
    expect(find.byTooltip('Highlight performance notes'), findsOneWidget);
    expect(find.byTooltip('Erase annotations'), findsOneWidget);
    expect(find.byTooltip('Undo annotation'), findsOneWidget);
    expect(find.byTooltip('Clear all performance notes'), findsOneWidget);
    expect(find.byTooltip('Align bars left'), findsOneWidget);
    expect(find.byTooltip('Align bars center'), findsOneWidget);
    expect(find.byTooltip('Align bars right'), findsOneWidget);
    expect(find.byTooltip('Use dark-on-light gig theme'), findsOneWidget);
    await tester.tap(find.byTooltip('Use dark-on-light gig theme'));
    await tester.pumpAndSettle();
    expect(preferences.value.gigTheme, GigThemePreference.darkOnLight);
    expect(find.byTooltip('Use light-on-black gig theme'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('1 / 2'))).brightness,
      Brightness.light,
    );
    expect(find.byKey(const Key('gig-zoom-slider')), findsOneWidget);
    expect(find.byKey(const Key('gig-song-zoom-slider')), findsOneWidget);
    expect(find.text('This song'), findsOneWidget);
    expect(find.text('Whole set'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gig-stage-surface')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gig-zoom-slider')), findsNothing);
    expect(find.byKey(const Key('gig-song-zoom-slider')), findsNothing);
    await tester.tap(find.byKey(const Key('gig-stage-surface')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gig-zoom-slider')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('gig-zoom-slider')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(preferences.value.gigZoom, isNot(0.75));
    expect(preferences.value.gigZoom, inInclusiveRange(0.45, 1.5));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);
    await tester.tap(find.byTooltip('Lock stage controls'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open setlist sidebar'), findsNothing);
    expect(find.byKey(const Key('gig-zoom-slider')), findsNothing);
    expect(find.byKey(const Key('gig-song-zoom-slider')), findsNothing);
    expect(find.byTooltip('Align bars left'), findsNothing);
    expect(find.byTooltip('Align bars center'), findsNothing);
    expect(find.byTooltip('Align bars right'), findsNothing);
    expect(find.byTooltip('Use light-on-black gig theme'), findsNothing);
    expect(find.byTooltip('Use dark-on-light gig theme'), findsNothing);
    expect(find.byTooltip('Unlock stage controls'), findsOneWidget);
    await tester.tap(find.byTooltip('Unlock stage controls'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gig-zoom-slider')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(performanceMode.values.last, isFalse);
    expect(find.text('Gig'), findsWidgets);
  });

  testWidgets(
    'gig annotation controls target every strip and undo the drawn strip',
    (tester) async {
      final now = DateTime.utc(2026, 7, 30);
      final library = _FakeLibrary()
        ..drafts.add(
          VisualChartDraft(
            id: 'multi-strip',
            title: 'Multi-strip chart',
            artist: '',
            createdAt: now,
            updatedAt: now,
            strips: const [
              VisualStrip(
                id: 'strip-a',
                assetHash: 'asset-a',
                assetExtension: 'png',
                pixelWidth: 100,
                pixelHeight: 40,
              ),
              VisualStrip(
                id: 'strip-b',
                assetHash: 'asset-b',
                assetExtension: 'png',
                pixelWidth: 100,
                pixelHeight: 40,
              ),
            ],
          ),
        )
        ..setlists.add(
          _setlist(
            'set-1',
            'Gig',
            entries: const [
              LibrarySetlistEntry(
                id: 'entry-0',
                chartVariantId: 'variant-multi-strip',
              ),
            ],
          ),
        );
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MusicTabblerApp(
          services: await _testServices(
            library: library,
            performanceDeckBuilder: _MultiStripPerformanceDeckBuilder(),
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

      await tester.tap(find.byTooltip('Hide annotations'));
      await tester.pumpAndSettle();
      expect(
        library.drafts.single.strips.every(
          (strip) => !strip.annotationsVisible,
        ),
        isTrue,
      );
      expect(find.byTooltip('Show annotations'), findsOneWidget);

      await tester.tap(find.byTooltip('Show annotations'));
      await tester.pumpAndSettle();
      expect(
        library.drafts.single.strips.every((strip) => strip.annotationsVisible),
        isTrue,
      );

      await tester.tap(find.byTooltip('Include annotations in PDF'));
      await tester.pumpAndSettle();
      expect(
        library.drafts.single.strips.every(
          (strip) => strip.includeAnnotationsInPdf,
        ),
        isTrue,
      );

      await tester.tap(find.byTooltip('Draw annotations'));
      await tester.pump();
      final secondStrip = find.byType(Image).at(1);
      final start = tester.getCenter(secondStrip) - const Offset(30, 0);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        library.drafts.single.strips
            .firstWhere((strip) => strip.id == 'strip-a')
            .annotations,
        isEmpty,
      );
      expect(
        library.drafts.single.strips
            .firstWhere((strip) => strip.id == 'strip-b')
            .annotations,
        hasLength(1),
      );

      await tester.tap(find.byTooltip('Undo annotation'));
      await tester.pumpAndSettle();
      expect(
        library.drafts.single.strips
            .firstWhere((strip) => strip.id == 'strip-b')
            .annotations,
        isEmpty,
      );
    },
  );

  testWidgets('gig mode exposes a safe exit while pages are preparing', (
    tester,
  ) async {
    final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
    final deckBuilder = _DelayedPerformanceDeckBuilder();
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
    await tester.pump();
    await tester.pump();

    expect(find.text('Preparing performance pages...'), findsOneWidget);
    expect(find.byTooltip('Exit gig mode'), findsOneWidget);

    await tester.tap(find.byTooltip('Exit gig mode'));
    await tester.pumpAndSettle();
    expect(performanceMode.values.last, isFalse);
    expect(find.text('Gig'), findsWidgets);
    deckBuilder.complete();
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
  LibraryStateTransfer? libraryState,
  DevicePreferencesStore? preferences,
  IncomingPdfReceiver? incomingPdf,
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
    preferences: preferences ?? _MemoryPreferencesStore(),
    performanceMode: performanceMode ?? _RecordingPerformanceModeController(),
    libraryState: libraryState,
    incomingPdf: incomingPdf,
  );
}

class _PendingPdfReceiver implements IncomingPdfReceiver {
  _PendingPdfReceiver(this._pending);

  IncomingPdf? _pending;

  @override
  Stream<void> get available => const Stream<void>.empty();

  @override
  Future<IncomingPdf?> takePendingPdf() async {
    final value = _pending;
    _pending = null;
    return value;
  }
}

class _RecordingLibraryStateTransfer implements LibraryStateTransfer {
  @override
  Future<Uint8List> exportStateBytes() async => Uint8List(0);

  @override
  Future<String?> exportStateWithPicker() async => null;

  @override
  Future<LibraryStateImportResult> importStateBytes(
    Uint8List bytes, {
    required StateImportMode mode,
    bool Function()? isCancelled,
  }) async => const LibraryStateImportResult(
    importedVariants: 0,
    skippedVariants: 0,
    importedSetlists: 0,
  );

  @override
  Future<LibraryStateImportResult?> importStateWithPicker(
    StateImportMode mode,
  ) async => null;

  @override
  Future<List<String>> listBackups() async => const [];

  @override
  Future<LibraryStateImportResult> restoreBackup(String path) async =>
      const LibraryStateImportResult(
        importedVariants: 0,
        skippedVariants: 0,
        importedSetlists: 0,
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
  int sharedPdfCalls = 0;

  @override
  Future<List<VisualStrip>> importPdfBytes(Uint8List bytes) async {
    sharedPdfCalls += 1;
    return pasteImages();
  }

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

class _FakeLibrary
    implements
        ChartLibrary,
        SongVariantLibrary,
        SetlistLibrary {
  final List<VisualChartDraft> drafts = [];
  final List<LibrarySetlist> setlists = [];

  @override
  String assetPath(String hash, String extension) => '';

  @override
  Future<StoredAsset> storeAsset(List<int> bytes, String extension) {
    throw UnimplementedError();
  }

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
  Future<List<VisualStrip>> importPdfBytes(Uint8List bytes) =>
      throw UnimplementedError();
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

class _RecordingVisualTabAnalyzer extends VisualTabAnalysisService {
  _RecordingVisualTabAnalyzer(ChartLibrary library)
    : super(library: library, textRecognition: const _UnusedTextRecognition());

  final List<bool> preferPositionedPdf = [];

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    this.preferPositionedPdf.add(preferPositionedPdf);
    return VisualTabAnalysis(
      stripId: strip.id,
      sourceType: preferPositionedPdf
          ? VisualTabSourceType.positionedPdf
          : VisualTabSourceType.rasterOcr,
      systems: [
        VisualTabSystem(
          id: '${strip.id}-system',
          rect: const NormalizedRect(0, 0.1, 1, 0.9),
          stringLines: const [0.2, 0.4, 0.6, 0.8],
          barLines: const [0.05, 0.95],
          tokens: [
            VisualTabToken(
              id: '${strip.id}-token',
              text: '5',
              rect: const NormalizedRect(0.4, 0.56, 0.44, 0.64),
              kind: VisualTabTokenKind.fret,
              stringIndex: 2,
            ),
          ],
        ),
      ],
    );
  }
}

class _BlockedVisualTabAnalyzer extends _RecordingVisualTabAnalyzer {
  _BlockedVisualTabAnalyzer(super.library);

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    if (strip.id == 'blocked-row') {
      return VisualTabAnalysis(
        stripId: strip.id,
        sourceType: VisualTabSourceType.rasterOcr,
      );
    }
    return super.analyze(
      strip,
      sourceStringCount: sourceStringCount,
      preferPositionedPdf: preferPositionedPdf,
    );
  }
}

class _SeamRiskVisualTabAnalyzer extends _RecordingVisualTabAnalyzer {
  _SeamRiskVisualTabAnalyzer(super.library);

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    final analysis = await super.analyze(
      strip,
      sourceStringCount: sourceStringCount,
      preferPositionedPdf: preferPositionedPdf,
    );
    final system = analysis.systems.single;
    return analysis.copyWith(
      systems: [
        system.copyWith(
          connectedNotationRisks: const [
            VisualConnectedNotationRisk(
              id: 'risk-1',
              rect: NormalizedRect(0.3, 0.46, 0.32, 0.54),
              gapIndex: 1,
            ),
            VisualConnectedNotationRisk(
              id: 'risk-2',
              rect: NormalizedRect(0.7, 0.46, 0.72, 0.54),
              gapIndex: 1,
            ),
          ],
        ),
      ],
    );
  }
}

class _UnusedExporter
    implements
        ChartPdfExporter,
        SetlistPdfExporter,
        PerformanceDeckBuilder {
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

class _MultiStripPerformanceDeckBuilder implements PerformanceDeckBuilder {
  static final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<PerformanceDeck> buildPerformanceDeck(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async => PerformanceDeck(
    setlistId: setlist.id,
    setlistName: setlist.name,
    density: density,
    pageWidth: 200,
    pageHeight: 100,
    margin: 5,
    gap: 2,
    pages: [
      PerformanceDeckPage(
        id: 'multi-strip-page',
        index: 0,
        elements: [
          for (var index = 0; index < 2; index += 1)
            PerformanceDeckElement(
              kind: PerformanceElementKind.strip,
              entryIndex: 0,
              entryId: 'entry-0',
              chartVariantId: 'variant-multi-strip',
              sourceStripId: 'strip-${index == 0 ? 'a' : 'b'}',
              sourceRowRect: const NormalizedRect(0, 0, 1, 1),
              rowIndex: index,
              width: 190,
              height: 44,
              imageBytes: _pixel,
            ),
        ],
      ),
    ],
  );
}

class _DelayedPerformanceDeckBuilder implements PerformanceDeckBuilder {
  final _completer = Completer<PerformanceDeck>();
  LibrarySetlist? _setlist;
  VisualExportDensity? _density;

  @override
  Future<PerformanceDeck> buildPerformanceDeck(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) {
    _setlist = setlist;
    _density = density;
    return _completer.future;
  }

  void complete() {
    if (_completer.isCompleted) return;
    final setlist = _setlist!;
    final density = _density!;
    _completer.complete(
      PerformanceDeck(
        setlistId: setlist.id,
        setlistName: setlist.name,
        density: density,
        pageWidth: 841.89,
        pageHeight: 595.28,
        margin: 5,
        gap: 0,
        pages: const [
          PerformanceDeckPage(
            id: 'delayed-page',
            index: 0,
            elements: [
              PerformanceDeckElement(
                kind: PerformanceElementKind.placeholder,
                entryIndex: 0,
                entryId: 'entry-0',
                title: 'Ready',
                width: 831.89,
                height: 22,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
