import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/portable_container.dart';

void main() {
  const codec = PortableContainerCodec();

  test('portable container round-trips deterministically with checksums', () {
    final first = codec.encode(
      kind: 'test',
      schemaVersion: 1,
      metadata: const {'name': 'fixture'},
      files: [
        PortableContainerFile(
          path: 'z/last.txt',
          bytes: Uint8List.fromList(utf8.encode('last')),
        ),
        PortableContainerFile(
          path: 'a/first.txt',
          bytes: Uint8List.fromList(utf8.encode('first')),
        ),
      ],
    );
    final second = codec.encode(
      kind: 'test',
      schemaVersion: 1,
      metadata: const {'name': 'fixture'},
      files: [
        PortableContainerFile(
          path: 'z/last.txt',
          bytes: Uint8List.fromList(utf8.encode('last')),
        ),
        PortableContainerFile(
          path: 'a/first.txt',
          bytes: Uint8List.fromList(utf8.encode('first')),
        ),
      ],
    );

    final restored = codec.decode(first, expectedKind: 'test');

    expect(first, second);
    expect(restored.schemaVersion, 1);
    expect(restored.metadata['name'], 'fixture');
    expect(restored.files.map((file) => file.path), [
      'a/first.txt',
      'z/last.txt',
    ]);
    expect(utf8.decode(restored.file('a/first.txt').bytes), 'first');
  });

  for (final path in [
    '../escape',
    'safe/../../escape',
    r'safe\escape',
    '/absolute',
    r'C:/drive',
    'safe//empty',
    'safe/./dot',
    'safe/\u0000nul',
  ]) {
    test('encode rejects unsafe path $path', () {
      expect(
        () => codec.encode(
          kind: 'test',
          schemaVersion: 1,
          files: [
            PortableContainerFile(path: path, bytes: Uint8List.fromList([1])),
          ],
        ),
        throwsA(isA<PortableContainerException>()),
      );
    });
  }

  test('case-insensitive path collisions are rejected', () {
    expect(
      () => codec.encode(
        kind: 'test',
        schemaVersion: 1,
        files: [
          PortableContainerFile(
            path: 'assets/A.png',
            bytes: Uint8List.fromList([1]),
          ),
          PortableContainerFile(
            path: 'assets/a.png',
            bytes: Uint8List.fromList([2]),
          ),
        ],
      ),
      throwsA(isA<PortableContainerException>()),
    );
  });

  test('tampering fails checksum validation', () {
    final valid = codec.encode(
      kind: 'test',
      schemaVersion: 1,
      files: [
        PortableContainerFile(
          path: 'payload.txt',
          bytes: Uint8List.fromList(utf8.encode('original')),
        ),
      ],
    );
    final archive = ZipDecoder().decodeBytes(valid);
    final manifest = archive.findFile(PortableContainerCodec.manifestPath)!;
    final tampered = Archive()
      ..add(ArchiveFile.bytes(manifest.name, manifest.readBytes()!))
      ..add(ArchiveFile.string('payload.txt', 'tampered'));

    expect(
      () => codec.decode(Uint8List.fromList(ZipEncoder().encode(tampered))),
      throwsA(isA<PortableContainerException>()),
    );
  });

  test('undeclared files and missing files are rejected', () {
    final valid = codec.encode(
      kind: 'test',
      schemaVersion: 1,
      files: [
        PortableContainerFile(
          path: 'payload.txt',
          bytes: Uint8List.fromList([1]),
        ),
      ],
    );
    final decoded = ZipDecoder().decodeBytes(valid);
    decoded.add(ArchiveFile.bytes('surprise.txt', [2]));

    expect(
      () => codec.decode(Uint8List.fromList(ZipEncoder().encode(decoded))),
      throwsA(isA<PortableContainerException>()),
    );
  });

  test('preflight rejects excessive expansion before reading content', () {
    const strict = PortableContainerCodec(
      limits: PortableContainerLimits(maxExpansionRatio: 2),
    );
    final archive = Archive()
      ..add(ArchiveFile.string('manifest.json', '{}'))
      ..add(ArchiveFile.bytes('zeros.bin', Uint8List(50000)));

    expect(
      () => strict.decode(Uint8List.fromList(ZipEncoder().encode(archive))),
      throwsA(isA<PortableContainerException>()),
    );
  });

  test('directories, symbolic links, and truncated ZIPs are rejected', () {
    final directory = Archive()..add(ArchiveFile.directory('folder/'));
    final symlinkArchive = Archive()
      ..add(ArchiveFile.string('link', '../outside'));
    final symlinkBytes = Uint8List.fromList(
      ZipEncoder().encode(symlinkArchive),
    );
    final symlinkData = ByteData.sublistView(symlinkBytes);
    final central = _findSignature(symlinkData, 0x02014b50);
    symlinkData.setUint16(central + 4, 0x0314, Endian.little);
    symlinkData.setUint32(central + 38, 0xA1FF0000, Endian.little);

    expect(
      () => codec.decode(Uint8List.fromList(ZipEncoder().encode(directory))),
      throwsA(isA<PortableContainerException>()),
    );
    expect(
      () => codec.decode(symlinkBytes),
      throwsA(isA<PortableContainerException>()),
    );
    expect(
      () => codec.decode(Uint8List.fromList([0x50, 0x4b, 0x03, 0x04])),
      throwsA(isA<PortableContainerException>()),
    );
  });

  test('kind mismatch and cancellation fail before installation', () {
    final valid = codec.encode(kind: 'song', schemaVersion: 1, files: const []);

    expect(
      () => codec.decode(valid, expectedKind: 'state'),
      throwsA(isA<PortableContainerException>()),
    );
    expect(
      () => codec.decode(valid, isCancelled: () => true),
      throwsA(isA<PortableContainerCancelled>()),
    );
  });
}

int _findSignature(ByteData data, int signature) {
  for (var offset = 0; offset <= data.lengthInBytes - 4; offset++) {
    if (data.getUint32(offset, Endian.little) == signature) return offset;
  }
  throw StateError('ZIP signature was not found.');
}
