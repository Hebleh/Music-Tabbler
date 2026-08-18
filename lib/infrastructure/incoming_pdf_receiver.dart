import 'dart:async';

import 'package:flutter/services.dart';

import '../application/portable_file_picker.dart';
import '../application/service_contracts.dart';

class MethodChannelIncomingPdfReceiver implements IncomingPdfReceiver {
  MethodChannelIncomingPdfReceiver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('music_tabbler/incoming_pdf') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedPdfAvailable') _available.add(null);
    });
  }

  final MethodChannel _channel;
  final StreamController<void> _available = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get available => _available.stream;

  @override
  Future<IncomingPdf?> takePendingPdf() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'takePendingPdf',
      );
      if (value == null) return null;
      final rawBytes = value['bytes'];
      final bytes = switch (rawBytes) {
        Uint8List value => value,
        List<int> value => Uint8List.fromList(value),
        _ => throw const PlatformFileReadException(
          'Android returned no readable data for the shared PDF.',
        ),
      };
      if (bytes.isEmpty) {
        throw const PlatformFileReadException(
          'The shared PDF is empty and cannot be imported.',
        );
      }
      final fileName = value['fileName'];
      return IncomingPdf(
        bytes: bytes,
        fileName: fileName is String && fileName.trim().isNotEmpty
            ? fileName.trim()
            : null,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw PlatformFileReadException(
        error.message ?? 'Android could not read the shared PDF.',
      );
    }
  }
}
