import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  test('library deduplicates assets and reloads saved visual drafts', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_library_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });

    final first = await library.storeAsset([1, 2, 3], 'png');
    final second = await library.storeAsset([1, 2, 3], '.png');
    final now = DateTime.utc(2026, 7, 20);
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'Saved chart',
      artist: 'Band',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'strip',
          assetHash: first.hash,
          assetExtension: first.extension,
          pixelWidth: 100,
          pixelHeight: 40,
        ),
      ],
    );

    await library.saveDraft(draft);
    final loaded = await library.listDrafts();

    expect(first.path, second.path);
    expect(File(first.path).existsSync(), isTrue);
    expect(loaded.single.title, 'Saved chart');
    expect(loaded.single.strips.single.assetHash, first.hash);

    await library.deleteDraft(draft.id);
    expect(await library.listDrafts(), isEmpty);
    expect(File(first.path).existsSync(), isTrue);
  });
}
