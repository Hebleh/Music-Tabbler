import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../domain/visual_chart_models.dart';
import 'service_contracts.dart';
import 'windows_clipboard_reader.dart';

class VisualImportService implements VisualImporter {
  VisualImportService(
    this.library, {
    this.clipboardReader = const WindowsClipboardReader(),
  });

  final ChartLibrary library;
  final WindowsClipboardReader clipboardReader;
  bool _pdfInitialized = false;

  @override
  Future<List<VisualStrip>> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    if (result == null) throw const ImportCancelled();
    final strips = <VisualStrip>[];
    for (final file in result.files) {
      final bytes = await _readPlatformFile(file);
      strips.add(await importImage(bytes, p.extension(file.name)));
    }
    return strips;
  }

  @override
  Future<List<VisualStrip>> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null) throw const ImportCancelled();
    final file = result.files.single;
    return importPdfBytes(await _readPlatformFile(file));
  }

  @override
  Future<List<VisualStrip>> pasteImages() async {
    if (!Platform.isWindows) {
      throw const VisualImportException(
        'Clipboard image import is Windows-only in this iteration.',
      );
    }
    final paths = await clipboardReader.readFilePaths();
    if (paths.isNotEmpty) {
      return importPaths(paths);
    }
    final bytes = await clipboardReader.readPng();
    if (bytes == null) {
      throw const VisualImportException(
        'The clipboard has no readable image or copied PNG/JPEG/PDF files.',
      );
    }
    return [await importImage(bytes, 'png')];
  }

  @override
  Future<List<VisualStrip>> importPaths(Iterable<String> paths) async {
    final files = <File>[];
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        final directoryFiles = Directory(path)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => _isSupportedPath(file.path));
        files.addAll(directoryFiles);
      } else if (type == FileSystemEntityType.file && _isSupportedPath(path)) {
        files.add(File(path));
      }
    }
    files.sort(
      (left, right) =>
          left.path.toLowerCase().compareTo(right.path.toLowerCase()),
    );
    if (files.isEmpty) {
      throw const VisualImportException(
        'Drop PNG, JPEG, or PDF files, or a folder containing them.',
      );
    }

    final strips = <VisualStrip>[];
    for (final file in files) {
      final extension = p.extension(file.path).toLowerCase();
      final bytes = await file.readAsBytes();
      if (extension == '.pdf') {
        strips.addAll(await importPdfBytes(bytes));
      } else {
        strips.add(await importImage(bytes, extension));
      }
    }
    return strips;
  }

  Future<VisualStrip> importImage(List<int> bytes, String extension) async {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const VisualImportException('The selected image is not valid.');
    }
    final original = await library.storeAsset(
      bytes,
      _cleanExtension(extension),
    );
    final normalized = img.bakeOrientation(decoded);
    final normalizedBytes = img.encodePng(normalized, level: 6);
    final displayAsset = await library.storeAsset(normalizedBytes, 'png');
    return VisualStrip(
      id: IdFactory.next('strip'),
      assetHash: displayAsset.hash,
      assetExtension: displayAsset.extension,
      pixelWidth: normalized.width,
      pixelHeight: normalized.height,
      sourceAssetHash: original.hash,
    );
  }

  @override
  Future<List<VisualStrip>> importPdfBytes(Uint8List bytes) => importPdf(bytes);

  Future<List<VisualStrip>> importPdf(List<int> bytes) async {
    if (!_pdfInitialized) {
      await pdfrxInitialize();
      _pdfInitialized = true;
    }
    final original = await library.storeAsset(bytes, 'pdf');
    final document = await PdfDocument.openFile(original.path);
    final strips = <VisualStrip>[];
    try {
      const scale = 160.0 / 72.0;
      for (var index = 0; index < document.pages.length; index += 1) {
        final page = document.pages[index];
        final rendered = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );
        if (rendered == null) {
          throw VisualImportException(
            'PDF page ${index + 1} could not render.',
          );
        }
        try {
          final image = rendered.createImageNF();
          final pngBytes = img.encodePng(image, level: 6);
          final pageAsset = await library.storeAsset(pngBytes, 'png');
          strips.add(
            VisualStrip(
              id: IdFactory.next('strip'),
              assetHash: pageAsset.hash,
              assetExtension: 'png',
              pixelWidth: image.width,
              pixelHeight: image.height,
              sourceAssetHash: original.hash,
              sourcePage: index + 1,
            ),
          );
        } finally {
          rendered.dispose();
        }
      }
    } finally {
      document.dispose();
    }
    return strips;
  }

  Future<Uint8List> _readPlatformFile(PlatformFile file) async {
    if (file.path case final path?) {
      return File(path).readAsBytes();
    }
    return file.xFile.readAsBytes();
  }

  String _cleanExtension(String value) {
    final extension = value.toLowerCase().replaceFirst('.', '');
    return switch (extension) {
      'jpeg' => 'jpg',
      'jpg' || 'png' => extension,
      _ => 'png',
    };
  }

  bool _isSupportedPath(String path) {
    return const {
      '.png',
      '.jpg',
      '.jpeg',
      '.pdf',
    }.contains(p.extension(path).toLowerCase());
  }
}
