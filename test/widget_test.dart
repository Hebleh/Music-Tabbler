import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/app.dart';
import 'package:music_tabbler/application/app_services.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

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
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(importer.pasteCalls, 1);
    expect(find.text('Row 1'), findsOneWidget);
  });
}

Future<AppServices> _testServices({VisualImporter? importer}) async {
  return AppServices(
    library: _FakeLibrary(),
    importer: importer ?? const _UnusedImporter(),
    exporter: const _UnusedExporter(),
    textRecognition: const _UnusedTextRecognition(),
  );
}

class _RecordingImporter implements VisualImporter {
  int pasteCalls = 0;

  @override
  Future<VisualStrip> pasteImage() async {
    pasteCalls += 1;
    return const VisualStrip(
      id: 'pasted',
      assetHash: 'asset',
      assetExtension: 'png',
      pixelWidth: 100,
      pixelHeight: 50,
    );
  }

  @override
  Future<List<VisualStrip>> importPaths(Iterable<String> paths) async => [];

  @override
  Future<List<VisualStrip>> pickImages() async => [];

  @override
  Future<List<VisualStrip>> pickPdf() async => [];
}

class _FakeLibrary implements ChartLibrary {
  final List<VisualChartDraft> drafts = [];

  @override
  String assetPath(String hash, String extension) => '';

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
}

class _UnusedImporter implements VisualImporter {
  const _UnusedImporter();
  @override
  Future<List<VisualStrip>> pickImages() => throw UnimplementedError();
  @override
  Future<List<VisualStrip>> pickPdf() => throw UnimplementedError();
  @override
  Future<VisualStrip> pasteImage() => throw UnimplementedError();
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

class _UnusedExporter implements ChartPdfExporter {
  const _UnusedExporter();
  @override
  Future<Uint8List> exportBytes(VisualChartDraft draft) =>
      throw UnimplementedError();
  @override
  Future<String?> exportWithPicker(VisualChartDraft draft) =>
      throw UnimplementedError();
}
