import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/portable_container.dart';
import 'package:music_tabbler/application/song_bundle_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  test(
    'mtsong round-trip preserves variants, assets, provenance, annotations',
    () async {
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_source_',
      );
      final targetDirectory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_target_',
      );
      final source = await LocalLibrary.forTesting(sourceDirectory);
      final target = await LocalLibrary.forTesting(targetDirectory);
      addTearDown(() {
        source.close();
        target.close();
        sourceDirectory.deleteSync(recursive: true);
        targetDirectory.deleteSync(recursive: true);
      });
      final image = img.Image(width: 100, height: 50)
        ..clear(img.ColorRgb8(255, 255, 255));
      final asset = await source.storeAsset(img.encodePng(image), 'png');
      final baseImage = img.Image(width: 100, height: 40)
        ..clear(img.ColorRgb8(20, 20, 20));
      final baseAsset = await source.storeAsset(
        img.encodePng(baseImage),
        'png',
      );
      final now = DateTime.utc(2026, 7, 24);
      VisualChartDraft draft(String id, String version) => VisualChartDraft(
        id: id,
        title: 'Portable Song',
        artist: 'Band',
        createdAt: now,
        updatedAt: now,
        provenance: SourceProvenance(
          url: 'https://example.com/$version',
          provider: 'Example',
          versionName: version,
        ),
        visualTabTransform: VisualTabTransformRecord(
          id: 'transform-$id',
          appliedAt: now,
          baseStrips: [
            VisualStrip(
              id: 'base-$id',
              assetHash: baseAsset.hash,
              assetExtension: baseAsset.extension,
              pixelWidth: 100,
              pixelHeight: 40,
            ),
          ],
          configuration: const {'globalPitchChange': 1},
          analyses: const [],
          audit: const ['fixture'],
        ),
        strips: [
          VisualStrip(
            id: 'strip-$id',
            assetHash: asset.hash,
            assetExtension: asset.extension,
            pixelWidth: 100,
            pixelHeight: 50,
            annotations: const [
              VisualAnnotationStroke(
                id: 'stroke',
                points: [
                  NormalizedPoint(0.1, 0.2, pressure: 0.4),
                  NormalizedPoint(0.9, 0.8, pressure: 0.8),
                ],
              ),
            ],
          ),
        ],
      );
      await source.saveDraftAsVariant(
        draft('variant-a', 'Original'),
        songId: 'song',
      );
      await source.saveDraftAsVariant(
        draft('variant-b', 'Stage'),
        songId: 'song',
      );
      final bytes = await SongBundleService(
        source,
      ).exportSongBytes('variant-a');
      final exported = const PortableContainerCodec().decode(
        bytes,
        expectedKind: SongBundleService.kind,
      );
      expect(exported.schemaVersion, 3);
      expect(exported.metadata, isNot(contains('semanticVariants')));
      final result = await SongBundleService(target).importSongBytes(bytes);

      expect(result.importedVariantIds, ['variant-a', 'variant-b']);
      expect((await target.listSongs()).single.id, 'song');
      expect(await target.listVariants('song'), hasLength(2));
      final restored = await target.loadDraft('variant-b');
      expect(restored!.provenance!.versionName, 'Stage');
      expect(
        restored.strips.single.annotations.single.points.last.pressure,
        0.8,
      );
      expect(
        await File(target.assetPath(asset.hash, asset.extension)).readAsBytes(),
        await File(source.assetPath(asset.hash, asset.extension)).readAsBytes(),
      );
      expect(
        await File(
          target.assetPath(baseAsset.hash, baseAsset.extension),
        ).readAsBytes(),
        await File(
          source.assetPath(baseAsset.hash, baseAsset.extension),
        ).readAsBytes(),
      );
    },
  );

  test(
    'mtsong v2 skips opaque semantic variants and imports visuals',
    () async {
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_legacy_source_',
      );
      final targetDirectory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_legacy_target_',
      );
      final source = await LocalLibrary.forTesting(sourceDirectory);
      final target = await LocalLibrary.forTesting(targetDirectory);
      addTearDown(() {
        source.close();
        target.close();
        sourceDirectory.deleteSync(recursive: true);
        targetDirectory.deleteSync(recursive: true);
      });
      final now = DateTime.utc(2026, 7, 24);
      await source.saveDraftAsVariant(
        VisualChartDraft(
          id: 'visual',
          title: 'Legacy mixed song',
          artist: 'Band',
          createdAt: now,
          updatedAt: now,
        ),
        songId: 'song',
      );
      final current = await SongBundleService(source).exportSongBytes('visual');
      const codec = PortableContainerCodec();
      final decoded = codec.decode(
        current,
        expectedKind: SongBundleService.kind,
      );
      final metadata = Map<String, Object?>.of(decoded.metadata)
        ..['semanticVariants'] = [
          {
            'id': 'legacy-semantic',
            'chartPath': 'semantic/0.json',
            'updatedAt': now.toIso8601String(),
          },
        ];
      final legacy = codec.encode(
        kind: SongBundleService.kind,
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

      final result = await SongBundleService(target).importSongBytes(legacy);

      expect(result.importedVariantIds, ['visual']);
      expect(result.skippedVariantIds, ['legacy-semantic']);
      expect(await target.loadDraft('visual'), isNotNull);
    },
  );

  test('semantic-only v2 bundle reports the retired variant', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_mtsong_semantic_only_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    final now = DateTime.utc(2026, 7, 24);
    const codec = PortableContainerCodec();
    final bundle = codec.encode(
      kind: SongBundleService.kind,
      schemaVersion: 2,
      metadata: {
        'song': {
          'id': 'legacy-song',
          'title': 'Legacy semantic song',
          'artist': 'Band',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        'variants': const [],
        'semanticVariants': [
          {
            'id': 'legacy-semantic',
            'chartPath': 'semantic/0.json',
            'updatedAt': now.toIso8601String(),
          },
        ],
      },
      files: [
        PortableContainerFile(
          path: 'semantic/0.json',
          bytes: Uint8List.fromList(utf8.encode('{"legacy":true}')),
        ),
      ],
    );

    final result = await SongBundleService(library).importSongBytes(bundle);

    expect(result.importedVariantIds, isEmpty);
    expect(result.skippedVariantIds, ['legacy-semantic']);
    expect(await library.listSongs(), isEmpty);
  });

  test(
    'malformed retired semantic payload does not modify the library',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_bad_semantic_',
      );
      final library = await LocalLibrary.forTesting(directory);
      addTearDown(() {
        library.close();
        directory.deleteSync(recursive: true);
      });
      final now = DateTime.utc(2026, 7, 24);
      await library.saveDraft(
        VisualChartDraft(
          id: 'safe',
          title: 'Safe',
          artist: '',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final malformed = const PortableContainerCodec().encode(
        kind: SongBundleService.kind,
        schemaVersion: 2,
        metadata: {
          'song': {
            'id': 'legacy-song',
            'title': 'Legacy',
            'artist': '',
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          },
          'variants': const [],
          'semanticVariants': [
            {
              'id': 'legacy-semantic',
              'chartPath': 'semantic/missing.json',
              'updatedAt': now.toIso8601String(),
            },
          ],
        },
        files: const [],
      );

      await expectLater(
        SongBundleService(library).importSongBytes(malformed),
        throwsA(isA<PortableContainerException>()),
      );
      expect(await library.loadDraft('safe'), isNotNull);
      expect(await library.listDrafts(), hasLength(1));
    },
  );

  test(
    'identical and divergent imports are retained as new variants',
    () async {
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_conflict_source_',
      );
      final targetDirectory = await Directory.systemTemp.createTemp(
        'music_tabbler_mtsong_conflict_target_',
      );
      final source = await LocalLibrary.forTesting(sourceDirectory);
      final target = await LocalLibrary.forTesting(targetDirectory);
      addTearDown(() {
        source.close();
        target.close();
        sourceDirectory.deleteSync(recursive: true);
        targetDirectory.deleteSync(recursive: true);
      });
      final now = DateTime.utc(2026, 7, 24);
      final original = VisualChartDraft(
        id: 'same-id',
        title: 'Original',
        artist: '',
        createdAt: now,
        updatedAt: now,
      );
      await source.saveDraftAsVariant(original, songId: 'song');
      final service = SongBundleService(target);
      final bundle = await SongBundleService(source).exportSongBytes('same-id');

      final first = await service.importSongBytes(bundle);
      final second = await service.importSongBytes(bundle);
      await target.saveDraft(
        original.copyWith(title: 'Local edit', updatedAt: now),
      );
      final divergent = await service.importSongBytes(bundle);

      expect(first.importedVariantIds, ['same-id']);
      expect(second.skippedVariantIds, isEmpty);
      expect(second.importedVariantIds.single, isNot('same-id'));
      expect(divergent.importedVariantIds.single, isNot('same-id'));
      expect(await target.listDrafts(), hasLength(3));
      expect(await target.listSongs(), hasLength(2));
      expect((await target.loadDraft('same-id'))!.title, 'Local edit');
    },
  );

  test('mtsong schema v1 remains importable', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'music_tabbler_mtsong_v1_source_',
    );
    final targetDirectory = await Directory.systemTemp.createTemp(
      'music_tabbler_mtsong_v1_target_',
    );
    final source = await LocalLibrary.forTesting(sourceDirectory);
    final target = await LocalLibrary.forTesting(targetDirectory);
    addTearDown(() {
      source.close();
      target.close();
      sourceDirectory.deleteSync(recursive: true);
      targetDirectory.deleteSync(recursive: true);
    });
    final now = DateTime.utc(2026, 7, 24);
    await source.saveDraftAsVariant(
      VisualChartDraft(
        id: 'legacy-visual',
        title: 'Legacy portable song',
        artist: '',
        createdAt: now,
        updatedAt: now,
      ),
      songId: 'legacy-song',
    );
    final encoded = await SongBundleService(
      source,
    ).exportSongBytes('legacy-visual');
    const codec = PortableContainerCodec();
    final current = codec.decode(encoded, expectedKind: SongBundleService.kind);
    final legacyMetadata = Map<String, Object?>.of(current.metadata)
      ..remove('semanticVariants');
    final legacy = codec.encode(
      kind: SongBundleService.kind,
      schemaVersion: 1,
      metadata: legacyMetadata,
      files: current.files,
    );

    final result = await SongBundleService(target).importSongBytes(legacy);

    expect(result.importedVariantIds, ['legacy-visual']);
    expect(await target.loadDraft('legacy-visual'), isNotNull);
  });

  test('corrupt mtsong does not install assets or drafts', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_mtsong_corrupt_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });

    await expectLater(
      SongBundleService(library).importSongBytes(Uint8List.fromList([1, 2, 3])),
      throwsException,
    );

    expect(await library.listDrafts(), isEmpty);
    expect(await library.assetsDirectory.list().toList(), isEmpty);
  });
}
