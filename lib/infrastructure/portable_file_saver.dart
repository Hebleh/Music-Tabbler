import 'package:flutter/services.dart';

import '../application/portable_file_picker.dart';

/// Saves Music Tabbler's private container formats without Android appending
/// `.zip` after inspecting their ZIP-based payloads.
class MethodChannelPortableFileSaver {
  const MethodChannelPortableFileSaver({
    this.channel = const MethodChannel('music_tabbler/portable_file'),
  });

  final MethodChannel channel;

  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      return await channel.invokeMethod<String>('saveFile', {
        'fileName': fileName,
        'bytes': bytes,
      });
    } on MissingPluginException {
      throw const PlatformFileReadException(
        'This build cannot save Android portable files.',
      );
    } on PlatformException catch (error) {
      throw PlatformFileReadException(
        error.message ?? 'Android could not save the portable file.',
      );
    }
  }
}
