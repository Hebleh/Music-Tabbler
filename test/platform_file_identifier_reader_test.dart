import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/portable_file_picker.dart';
import 'package:music_tabbler/infrastructure/platform_file_identifier_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('music_tabbler/platform_file_test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads bytes for a selected Android content URI', () async {
    final expected = Uint8List.fromList([4, 3, 2, 1]);
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return expected;
        });

    final actual = await const MethodChannelPlatformFileIdentifierReader(
      channel: channel,
    ).read('content://documents/chart.pdf');

    expect(received?.method, 'readBytes');
    expect(received?.arguments, 'content://documents/chart.pdf');
    expect(actual, expected);
  });

  test('turns native read failures into a useful import error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'read_failed',
            message: 'The provider denied access.',
          );
        });

    expect(
      () => const MethodChannelPlatformFileIdentifierReader(
        channel: channel,
      ).read('content://documents/chart.pdf'),
      throwsA(
        isA<PlatformFileReadException>().having(
          (error) => error.message,
          'message',
          'The provider denied access.',
        ),
      ),
    );
  });
}
