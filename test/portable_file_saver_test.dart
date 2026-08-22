import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/portable_file_picker.dart';
import 'package:music_tabbler/infrastructure/portable_file_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('music_tabbler/portable_file_test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('passes the exact private extension and bytes to Android', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return 'content://downloads/document/portable';
        });
    final bytes = Uint8List.fromList(const [80, 75, 3, 4]);

    final result = await const MethodChannelPortableFileSaver(
      channel: channel,
    ).save(fileName: 'song.mtsong', bytes: bytes);

    expect(result, 'content://downloads/document/portable');
    expect(received!.method, 'saveFile');
    expect(received!.arguments, {'fileName': 'song.mtsong', 'bytes': bytes});
  });

  test('replaces a null native error with an actionable message', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'save_failed'),
        );

    await expectLater(
      const MethodChannelPortableFileSaver(
        channel: channel,
      ).save(fileName: 'library.mtstate', bytes: Uint8List(1)),
      throwsA(
        isA<PlatformFileReadException>().having(
          (error) => error.message,
          'message',
          'Android could not save the portable file.',
        ),
      ),
    );
  });
}
