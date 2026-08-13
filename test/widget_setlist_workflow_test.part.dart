part of 'widget_test.dart';

void _registerSetlistWorkflowTests() {
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
}
