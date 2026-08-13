import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/library_state_service.dart';
import 'package:music_tabbler/application/portable_container.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/domain/library_models.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  test(
    'mtstate replacement round-trips songs, assets, setlists, and backup',
    () async {
      final sourceFixture = await _fixture('state-source');
      final targetFixture = await _fixture('state-target');
      addTearDown(sourceFixture.dispose);
      addTearDown(targetFixture.dispose);
      await _saveChart(sourceFixture.library, 'source-chart', 'Source song');
      await sourceFixture.library.saveSetlist(
        _setlist('source-set', 'source-chart'),
      );
      await _saveChart(targetFixture.library, 'old-chart', 'Old song');

      final bytes = await LibraryStateService(
        sourceFixture.library,
      ).exportStateBytes();
      final exported = const PortableContainerCodec().decode(
        bytes,
        expectedKind: LibraryStateService.kind,
      );
      expect(exported.schemaVersion, 3);
      expect(exported.metadata, isNot(contains('semanticVariants')));
      final targetService = LibraryStateService(targetFixture.library);
      final result = await targetService.importStateBytes(
        bytes,
        mode: StateImportMode.replace,
      );

      expect(result.importedVariants, 1);
      expect(result.importedSetlists, 1);
      expect(result.backupPath, isNotNull);
      expect(await File(result.backupPath!).exists(), isTrue);
      expect(await targetFixture.library.loadDraft('old-chart'), isNull);
      expect(
        (await targetFixture.library.loadDraft('source-chart'))!.title,
        'Source song',
      );
      final restoredDraft = await targetFixture.library.loadDraft(
        'source-chart',
      );
      final restoredAnalysis = VisualTabAnalysis.fromJson(
        restoredDraft!.visualTabTransform!.analyses.single,
      );
      expect(
        restoredAnalysis.systems.single.tokens.single.origin,
        VisualTabTokenOrigin.manual,
      );
      expect(
        (await targetFixture.library.loadSetlist(
          'source-set',
        ))!.entries.single.chartVariantId,
        'source-chart',
      );
    },
  );

  test(
    'mtstate v2 retains visual state and reports retired semantics',
    () async {
      final sourceFixture = await _fixture('legacy-state-source');
      final targetFixture = await _fixture('legacy-state-target');
      addTearDown(sourceFixture.dispose);
      addTearDown(targetFixture.dispose);
      await _saveChart(sourceFixture.library, 'visual-source', 'Visual source');
      final current = await LibraryStateService(
        sourceFixture.library,
      ).exportStateBytes();
      const codec = PortableContainerCodec();
      final decoded = codec.decode(
        current,
        expectedKind: LibraryStateService.kind,
      );
      final metadata = Map<String, Object?>.of(decoded.metadata);
      metadata['semanticVariants'] = [
        {
          'id': 'semantic-source',
          'songId': 'song-visual-source',
          'chartPath': 'semantic/0.json',
          'updatedAt': DateTime.utc(2026, 7, 25).toIso8601String(),
        },
      ];
      metadata['setlists'] = [
        {
          'id': 'legacy-semantic-set',
          'name': 'Legacy set',
          'scheduledAt': null,
          'notes': null,
          'createdAt': DateTime.utc(2026, 7, 25).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 7, 25).toIso8601String(),
          'entries': [
            {
              'id': 'legacy-semantic-entry',
              'kind': 'chart',
              'chartVariantId': 'semantic-source',
              'placeholderTitle': null,
            },
          ],
        },
      ];
      final legacy = codec.encode(
        kind: LibraryStateService.kind,
        schemaVersion: 2,
        metadata: metadata,
        files: [
          ...decoded.files,
          PortableContainerFile(
            path: 'semantic/0.json',
            bytes: Uint8List.fromList(utf8.encode('{"legacy":true}')),
          ),
        ],
      );
      final result = await LibraryStateService(
        targetFixture.library,
      ).importStateBytes(legacy, mode: StateImportMode.replace);

      expect(result.importedVariants, 1);
      expect(result.skippedVariants, 1);
      expect(result.skippedVariantIds, ['semantic-source']);
      expect(await targetFixture.library.loadDraft('visual-source'), isNotNull);
      final setlist = await targetFixture.library.loadSetlist(
        'legacy-semantic-set',
      );
      expect(setlist!.entries.single.placeholderTitle, 'Visual source');
    },
  );

  test('mtstate v1 remains importable without semantic metadata', () async {
    final sourceFixture = await _fixture('legacy-state-source');
    final targetFixture = await _fixture('legacy-state-target');
    addTearDown(sourceFixture.dispose);
    addTearDown(targetFixture.dispose);
    await _saveChart(sourceFixture.library, 'legacy-chart', 'Legacy chart');
    final current = await LibraryStateService(
      sourceFixture.library,
    ).exportStateBytes();
    const codec = PortableContainerCodec();
    final decoded = codec.decode(
      current,
      expectedKind: LibraryStateService.kind,
    );
    final metadata = Map<String, Object?>.of(decoded.metadata)
      ..remove('semanticVariants');
    final legacy = codec.encode(
      kind: LibraryStateService.kind,
      schemaVersion: 1,
      metadata: metadata,
      files: [
        for (final file in decoded.files)
          PortableContainerFile(path: file.path, bytes: file.bytes),
      ],
    );

    await LibraryStateService(
      targetFixture.library,
    ).importStateBytes(legacy, mode: StateImportMode.replace);

    expect(await targetFixture.library.loadDraft('legacy-chart'), isNotNull);
  });

  test(
    'corrupt and cancelled state imports leave live state unchanged',
    () async {
      final fixture = await _fixture('state-unchanged');
      addTearDown(fixture.dispose);
      await _saveChart(fixture.library, 'safe-chart', 'Safe song');
      final service = LibraryStateService(fixture.library);
      final before = await service.exportStateBytes();

      await expectLater(
        service.importStateBytes(
          Uint8List.fromList([1, 2, 3]),
          mode: StateImportMode.replace,
        ),
        throwsA(isA<PortableContainerException>()),
      );
      await expectLater(
        service.importStateBytes(
          before,
          mode: StateImportMode.replace,
          isCancelled: () => true,
        ),
        throwsA(isA<PortableContainerCancelled>()),
      );

      expect(await service.exportStateBytes(), before);
      expect(await service.listBackups(), isEmpty);
    },
  );

  test(
    'duplicate staged identities fail before backup or installation',
    () async {
      final sourceFixture = await _fixture('state-duplicate-source');
      final targetFixture = await _fixture('state-duplicate-target');
      addTearDown(sourceFixture.dispose);
      addTearDown(targetFixture.dispose);
      await _saveChart(sourceFixture.library, 'incoming', 'Incoming');
      await sourceFixture.library.saveSetlist(
        _setlist('duplicate', 'incoming'),
      );
      await _saveChart(targetFixture.library, 'safe', 'Safe');
      final sourceState = await LibraryStateService(
        sourceFixture.library,
      ).exportStateBytes();
      const codec = PortableContainerCodec();
      final decoded = codec.decode(
        sourceState,
        expectedKind: LibraryStateService.kind,
      );
      final metadata = Map<String, Object?>.of(decoded.metadata);
      final setlists = List<Object?>.of(metadata['setlists']! as List);
      metadata['setlists'] = [setlists.single, setlists.single];
      final duplicateState = codec.encode(
        kind: LibraryStateService.kind,
        schemaVersion: LibraryStateService.schemaVersion,
        metadata: metadata,
        files: [
          for (final file in decoded.files)
            PortableContainerFile(path: file.path, bytes: file.bytes),
        ],
      );
      final service = LibraryStateService(targetFixture.library);

      await expectLater(
        service.importStateBytes(duplicateState, mode: StateImportMode.replace),
        throwsA(isA<PortableContainerException>()),
      );

      expect(await targetFixture.library.loadDraft('safe'), isNotNull);
      expect(await service.listBackups(), isEmpty);
    },
  );

  test(
    'an existing corrupt asset aborts before backup or database changes',
    () async {
      final sourceFixture = await _fixture('state-corrupt-asset-source');
      final targetFixture = await _fixture('state-corrupt-asset-target');
      addTearDown(sourceFixture.dispose);
      addTearDown(targetFixture.dispose);
      await _saveChart(sourceFixture.library, 'incoming', 'Incoming');
      await _saveChart(targetFixture.library, 'safe', 'Safe');
      final incoming = await LibraryStateService(
        sourceFixture.library,
      ).exportStateBytes();
      final targetDraft = (await targetFixture.library.loadDraft('safe'))!;
      final targetStrip = targetDraft.strips.single;
      final targetAsset = File(
        targetFixture.library.assetPath(
          targetStrip.assetHash,
          targetStrip.assetExtension,
        ),
      );
      await targetAsset.writeAsBytes([1, 2, 3], flush: true);
      final service = LibraryStateService(targetFixture.library);

      await expectLater(
        service.importStateBytes(incoming, mode: StateImportMode.replace),
        throwsA(isA<PortableContainerException>()),
      );

      expect(await targetFixture.library.loadDraft('safe'), isNotNull);
      expect(await targetFixture.library.loadDraft('incoming'), isNull);
      expect(await targetAsset.readAsBytes(), [1, 2, 3]);
      expect(await service.listBackups(), isEmpty);
    },
  );

  test(
    'merge preserves divergent local data and remaps imported references',
    () async {
      final sourceFixture = await _fixture('state-merge-source');
      final targetFixture = await _fixture('state-merge-target');
      addTearDown(sourceFixture.dispose);
      addTearDown(targetFixture.dispose);
      await _saveChart(sourceFixture.library, 'shared-id', 'Imported version');
      await sourceFixture.library.saveSetlist(
        _setlist('shared-set', 'shared-id'),
      );
      await _saveChart(targetFixture.library, 'shared-id', 'Local version');
      await targetFixture.library.saveSetlist(
        _setlist('shared-set', 'shared-id'),
      );
      final state = await LibraryStateService(
        sourceFixture.library,
      ).exportStateBytes();

      final result = await LibraryStateService(
        targetFixture.library,
      ).importStateBytes(state, mode: StateImportMode.merge);

      expect(result.importedVariants, 1);
      expect(await targetFixture.library.listDrafts(), hasLength(2));
      expect(await targetFixture.library.listSetlists(), hasLength(2));
      expect(
        (await targetFixture.library.loadDraft('shared-id'))!.title,
        'Local version',
      );
      final importedSet = (await targetFixture.library.listSetlists())
          .singleWhere((setlist) => setlist.id != 'shared-set');
      expect(importedSet.entries.single.chartVariantId, isNot('shared-id'));
    },
  );

  test(
    'restore recovers the prior state and backup retention stays at five',
    () async {
      final fixture = await _fixture('state-restore');
      final replacement = await _fixture('state-replacement');
      addTearDown(fixture.dispose);
      addTearDown(replacement.dispose);
      await _saveChart(fixture.library, 'original', 'Original');
      await _saveChart(replacement.library, 'replacement', 'Replacement');
      final replacementState = await LibraryStateService(
        replacement.library,
      ).exportStateBytes();
      final service = LibraryStateService(fixture.library);

      await service.importStateBytes(
        replacementState,
        mode: StateImportMode.replace,
      );
      final originalBackup = (await service.listBackups()).single;
      await service.restoreBackup(originalBackup);

      expect(await fixture.library.loadDraft('original'), isNotNull);
      expect(await fixture.library.loadDraft('replacement'), isNull);

      for (var index = 0; index < 6; index++) {
        await service.importStateBytes(
          replacementState,
          mode: StateImportMode.replace,
        );
      }
      expect(await service.listBackups(), hasLength(5));
    },
  );
}

Future<_LibraryFixture> _fixture(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(
    'music_tabbler_$prefix',
  );
  return _LibraryFixture(directory, await LocalLibrary.forTesting(directory));
}

Future<void> _saveChart(LocalLibrary library, String id, String title) async {
  final image = img.Image(width: 80, height: 40)
    ..clear(img.ColorRgb8(255, 255, 255));
  final asset = await library.storeAsset(img.encodePng(image), 'png');
  final now = DateTime.utc(2026, 7, 24);
  await library.saveDraftAsVariant(
    VisualChartDraft(
      id: id,
      title: title,
      artist: 'Band',
      createdAt: now,
      updatedAt: now,
      visualTabTransform: VisualTabTransformRecord(
        id: 'transform-$id',
        appliedAt: now,
        baseStrips: [
          VisualStrip(
            id: 'base-$id',
            assetHash: asset.hash,
            assetExtension: asset.extension,
            pixelWidth: 80,
            pixelHeight: 40,
          ),
        ],
        configuration: const {'globalPitchChange': 0},
        analyses: [
          const VisualTabAnalysis(
            stripId: 'manual-source',
            sourceType: VisualTabSourceType.rasterOcr,
            systems: [
              VisualTabSystem(
                id: 'system',
                rect: NormalizedRect(0, 0, 1, 1),
                stringLines: [0.2, 0.4, 0.6, 0.8],
                tokens: [
                  VisualTabToken(
                    id: 'manual-note',
                    text: 'X',
                    rect: NormalizedRect(0.4, 0.56, 0.45, 0.64),
                    kind: VisualTabTokenKind.deadNote,
                    stringIndex: 1,
                    origin: VisualTabTokenOrigin.manual,
                  ),
                ],
              ),
            ],
          ).toJson(),
        ],
      ),
      strips: [
        VisualStrip(
          id: 'strip-$id',
          assetHash: asset.hash,
          assetExtension: asset.extension,
          pixelWidth: 80,
          pixelHeight: 40,
        ),
      ],
    ),
    songId: 'song-$id',
  );
}

LibrarySetlist _setlist(String id, String chartId) {
  final now = DateTime.utc(2026, 7, 24);
  return LibrarySetlist(
    id: id,
    name: 'Gig $id',
    createdAt: now,
    updatedAt: now,
    entries: [LibrarySetlistEntry(id: 'entry-$id', chartVariantId: chartId)],
  );
}

class _LibraryFixture {
  const _LibraryFixture(this.directory, this.library);

  final Directory directory;
  final LocalLibrary library;

  void dispose() {
    library.close();
    directory.deleteSync(recursive: true);
  }
}
