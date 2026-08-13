part of 'widget_test.dart';

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

class _FakeLibrary implements ChartLibrary, SongVariantLibrary, SetlistLibrary {
  _FakeLibrary({this.analysisAssetPath = ''});

  final String analysisAssetPath;
  final List<VisualChartDraft> drafts = [];
  final List<LibrarySetlist> setlists = [];

  @override
  String assetPath(String hash, String extension) => analysisAssetPath;

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

class _DelayedThirdVisualTabAnalyzer extends _RecordingVisualTabAnalyzer {
  _DelayedThirdVisualTabAnalyzer(super.library);

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    if (strip.id == 'tap-row-c') {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return super.analyze(
      strip,
      sourceStringCount: sourceStringCount,
      preferPositionedPdf: preferPositionedPdf,
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
