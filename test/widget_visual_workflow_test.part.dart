part of 'widget_test.dart';

void _registerVisualWorkflowTests() {
  testWidgets('source string dialog previews the raster geometry guess', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showVisualSourceStringCountDialog(
                context: context,
                guess: Future.value(
                  const VisualTabStringCountGuess(
                    stringCount: 8,
                    geometryConfidence: 0.98,
                    detectedBarLines: 4,
                  ),
                ),
              ),
              child: const Text('Open string preview'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open string preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('raster-string-count-guess')),
      findsOneWidget,
    );
    expect(find.text('Raster preview: 8 strings detected'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '8');
  });

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

  testWidgets(
    'visual tab review automatically runs every row through raster OCR',
    (tester) async {
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
      expect(analyzer.preferPositionedPdf, [isFalse, isFalse]);
      expect(find.byKey(const ValueKey('raster-ocr-all-rows')), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
    },
  );

  testWidgets('draw missing token opens the editor from one canvas tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previewDirectory = Directory.systemTemp.createTempSync(
      'analysis-guide-preview-',
    );
    addTearDown(() => previewDirectory.deleteSync(recursive: true));
    final preview = File('${previewDirectory.path}/preview.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAZAAAABkCAYAAACoy2Z3AAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAABkKADAAQAAAABAAAAZAAAAABt2Ur0AAAC0klEQVR4Ae3QMQEAAADCoPVPbQ0PiEBhwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwIABAwYMGDBgwICBn4EBcYIAAXG5ZYUAAAAASUVORK5CYII=',
        ),
      );
    final library = _FakeLibrary(analysisAssetPath: preview.path);
    final analyzer = _DelayedThirdVisualTabAnalyzer(library);
    var parentUndoCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
                parentUndoCount += 1,
          },
          child: Focus(
            autofocus: true,
            child: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showVisualTabAnalysisReview(
                    context: context,
                    library: library,
                    analyzer: analyzer,
                    strips: const [
                      VisualStrip(
                        id: 'tap-row-a',
                        assetHash: 'missing-preview-a',
                        assetExtension: 'png',
                        pixelWidth: 400,
                        pixelHeight: 100,
                      ),
                      VisualStrip(
                        id: 'tap-row-b',
                        assetHash: 'missing-preview-b',
                        assetExtension: 'png',
                        pixelWidth: 400,
                        pixelHeight: 100,
                      ),
                      VisualStrip(
                        id: 'tap-row-c',
                        assetHash: 'missing-preview-c',
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
        ),
      ),
    );

    await tester.tap(find.text('Open review'));
    for (var index = 0; index < 4; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    await tester.tap(find.text('Draw missing token'));
    await tester.pump();
    final drawSurface = find.byKey(
      const ValueKey('analysis-draw-surface-tap-row-b'),
    );
    final drawBounds = tester.getRect(drawSurface);
    await tester.tapAt(
      Offset(drawBounds.center.dx, drawBounds.top + drawBounds.height * 0.6),
    );
    await tester.pump();

    expect(find.text('Review detected token'), findsOneWidget);

    expect(find.text('String 2 (low to high)'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '7');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Review detected token'), findsNothing);
    expect(find.text('7'), findsWidgets);
    expect(find.text('fret · string 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-string-guide-tap-row-b')),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(parentUndoCount, 0);
    expect(find.text('fret · string 2'), findsNothing);
    expect(
      find.byKey(const ValueKey('analysis-string-guide-tap-row-b')),
      findsNothing,
    );

    await tester.tap(find.text('Draw missing token'));
    await tester.pump();
    await tester.tapAt(
      Offset(drawBounds.center.dx, drawBounds.top + drawBounds.height * 0.6),
    );
    await tester.pump();
    expect(find.text('Review detected token'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    for (var index = 0; index < 6; index += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Open review'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    'visual tab review screen keeps row canvas and inspector visible',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final library = _FakeLibrary();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showVisualTabAnalysisReview(
                  context: context,
                  library: library,
                  analyzer: _SeamRiskVisualTabAnalyzer(library),
                  strips: const [
                    VisualStrip(
                      id: 'golden-row',
                      assetHash: 'golden',
                      assetExtension: 'png',
                      pixelWidth: 1200,
                      pixelHeight: 180,
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

      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/windows/analysis_review_screen.png'),
      );
    },
    skip: !Platform.isWindows,
  );

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
}
