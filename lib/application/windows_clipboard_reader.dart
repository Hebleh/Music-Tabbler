import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

class WindowsClipboardReader {
  const WindowsClipboardReader();

  Future<Uint8List?> readPng() async {
    if (!Platform.isWindows) return null;
    for (var attempt = 0; attempt < 5; attempt += 1) {
      if (OpenClipboard(0) != 0) {
        try {
          var handle = GetClipboardData(CF_DIBV5);
          if (handle == 0) handle = GetClipboardData(CF_DIB);
          if (handle == 0) return null;
          final memory = Pointer.fromAddress(handle);
          final size = GlobalSize(memory);
          final locked = GlobalLock(memory);
          if (size <= 0 || locked == nullptr) return null;
          try {
            final dib = Uint8List.fromList(
              locked.cast<Uint8>().asTypedList(size),
            );
            final decoded = img.decodeBmp(_dibToBmp(dib));
            if (decoded == null) return null;
            return Uint8List.fromList(img.encodePng(decoded, level: 6));
          } finally {
            GlobalUnlock(memory);
          }
        } finally {
          CloseClipboard();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  Uint8List _dibToBmp(Uint8List dib) {
    if (dib.length < 40) {
      throw const FormatException('Clipboard bitmap header is incomplete.');
    }
    final source = ByteData.sublistView(dib);
    final headerSize = source.getUint32(0, Endian.little);
    final bitCount = source.getUint16(14, Endian.little);
    final compression = source.getUint32(16, Endian.little);
    final colorsUsed = source.getUint32(32, Endian.little);
    final paletteEntries = colorsUsed != 0
        ? colorsUsed
        : bitCount <= 8
        ? 1 << bitCount
        : 0;
    final maskBytes = headerSize == 40 && (compression == 3 || compression == 6)
        ? (compression == 6 ? 16 : 12)
        : 0;
    final pixelOffset = 14 + headerSize + maskBytes + paletteEntries * 4;
    final output = Uint8List(14 + dib.length);
    final header = ByteData.sublistView(output);
    header.setUint8(0, 0x42);
    header.setUint8(1, 0x4D);
    header.setUint32(2, output.length, Endian.little);
    header.setUint32(10, pixelOffset, Endian.little);
    output.setRange(14, output.length, dib);
    return output;
  }
}
