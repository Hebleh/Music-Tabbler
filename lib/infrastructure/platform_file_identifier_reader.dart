import 'package:flutter/services.dart';

import '../application/portable_file_picker.dart';

/// Reads an Android document-provider URI when `file_picker` cannot expose a
/// durable filesystem path or eagerly loaded bytes.
class MethodChannelPlatformFileIdentifierReader {
  const MethodChannelPlatformFileIdentifierReader({
    this.channel = const MethodChannel('music_tabbler/platform_file'),
  });

  final MethodChannel channel;

  Future<Uint8List> read(String identifier) async {
    try {
      final bytes = await channel.invokeMethod<Uint8List>(
        'readBytes',
        identifier,
      );
      if (bytes == null) {
        throw const PlatformFileReadException(
          'Android did not return data for the selected file.',
        );
      }
      return bytes;
    } on MissingPluginException {
      throw const PlatformFileReadException(
        'This build cannot read Android document-provider files.',
      );
    } on PlatformException catch (error) {
      throw PlatformFileReadException(
        error.message ?? 'Android could not read the selected file.',
      );
    }
  }
}
