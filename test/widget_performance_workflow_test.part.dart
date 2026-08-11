part of 'widget_test.dart';

void _registerPerformanceWorkflowTests() {
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
    'gig mode toolbar keeps its unlocked stage controls',
    (tester) async {
      final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MusicTabblerApp(
          services: await _testServices(
            library: library,
            performanceDeckBuilder: _RecordingPerformanceDeckBuilder(),
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

      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/windows/gig_mode_toolbar.png'),
      );
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'gig mode setlist drawer keeps its stage navigation shell',
    (tester) async {
      final library = _FakeLibrary()..setlists.add(_setlist('set-1', 'Gig'));
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MusicTabblerApp(
          services: await _testServices(
            library: library,
            performanceDeckBuilder: _RecordingPerformanceDeckBuilder(),
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
      await tester.tap(find.byTooltip('Open setlist sidebar'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/windows/gig_setlist_drawer.png'),
      );
    },
    skip: !Platform.isWindows,
  );

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
