import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/infrastructure/incoming_pdf_receiver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('music_tabbler/incoming_pdf_test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('takes shared PDF bytes and the host display name', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'takePendingPdf');
          return {
            'bytes': Uint8List.fromList([37, 80, 68, 70]),
            'fileName': 'shared tab.pdf',
          };
        });
    final receiver = MethodChannelIncomingPdfReceiver(channel: channel);

    final incoming = await receiver.takePendingPdf();

    expect(incoming, isNotNull);
    expect(incoming!.bytes, [37, 80, 68, 70]);
    expect(incoming.fileName, 'shared tab.pdf');
  });

  test('returns null when no shared PDF is pending', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final receiver = MethodChannelIncomingPdfReceiver(channel: channel);

    expect(await receiver.takePendingPdf(), isNull);
  });
}
