import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/service_contracts.dart';
import '../../domain/visual_chart_models.dart';
import 'rect_editor_dialog.dart';
import 'visual_strip_preview.dart';

class VisualImportScreen extends StatefulWidget {
  const VisualImportScreen({
    super.key,
    required this.services,
    this.initialDraft,
  });

  final AppServices services;
  final VisualChartDraft? initialDraft;

  @override
  State<VisualImportScreen> createState() => _VisualImportScreenState();
}

class _VisualImportScreenState extends State<VisualImportScreen> {
  late VisualChartDraft _draft;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _draft =
        widget.initialDraft ??
        VisualChartDraft(
          id: IdFactory.next('chart'),
          title: 'Untitled chart',
          artist: '',
          createdAt: now,
          updatedAt: now,
        );
    _titleController = TextEditingController(text: _draft.title);
    _artistController = TextEditingController(text: _draft.artist);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual chart editor'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy || _draft.strips.isEmpty ? null : _export,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export A4'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Song title',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _artistController,
                          decoration: const InputDecoration(
                            labelText: 'Artist',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<VisualTreatment?>(
                        value: _draft.globalTreatment,
                        hint: const Text('Per-strip display'),
                        onChanged: (value) => setState(() {
                          _draft = value == null
                              ? _draft.copyWith(clearGlobalTreatment: true)
                              : _draft.copyWith(globalTreatment: value);
                        }),
                        items: [
                          const DropdownMenuItem<VisualTreatment?>(
                            value: null,
                            child: Text('Per-strip display'),
                          ),
                          ...VisualTreatment.values.map(
                            (value) => DropdownMenuItem<VisualTreatment?>(
                              value: value,
                              child: Text('Whole tab: ${value.label}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      FilterChip(
                        label: const Text('Title / artist in PDF'),
                        selected: _draft.showHeader,
                        onSelected: (value) => setState(() {
                          _draft = _draft.copyWith(showHeader: value);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _add(_ImportKind.images),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add PNG / JPEG'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _add(_ImportKind.pdf),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Add PDF'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _add(_ImportKind.clipboard),
                        icon: const Icon(Icons.content_paste_outlined),
                        label: const Text('Paste image'),
                      ),
                      if (_busy)
                        const SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _draft.strips.isEmpty
                ? const _EmptyImportState()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _draft.strips.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final strip = _draft.strips[index];
                      return _StripCard(
                        key: ValueKey(strip.id),
                        index: index,
                        strip: strip,
                        globalTreatment: _draft.globalTreatment,
                        services: widget.services,
                        onChanged: (value) => _replaceStrip(index, value),
                        onCrop: () => _editCrop(index),
                        onLyricBand: () => _editLyricBand(index),
                        onAddHighlight: () => _addHighlight(index),
                        onDuplicate: () => _duplicate(index),
                        onDelete: () => _delete(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(_ImportKind kind) async {
    setState(() => _busy = true);
    try {
      final additions = switch (kind) {
        _ImportKind.images => await widget.services.importer.pickImages(),
        _ImportKind.pdf => await widget.services.importer.pickPdf(),
        _ImportKind.clipboard => [await widget.services.importer.pasteImage()],
      };
      if (!mounted) return;
      setState(() {
        _draft = _draft.copyWith(strips: [..._draft.strips, ...additions]);
      });
    } on ImportCancelled {
      // Native picker cancellation is not an error.
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCrop(int index) async {
    final strip = _draft.strips[index];
    final value = await showDialog<NormalizedRect>(
      context: context,
      builder: (_) => RectEditorDialog(
        imagePath: widget.services.library.assetPath(
          strip.assetHash,
          strip.assetExtension,
        ),
        imageAspectRatio: strip.pixelWidth / strip.pixelHeight,
        title: 'Crop tab row',
        initialRect: strip.crop,
      ),
    );
    if (value != null) _replaceStrip(index, strip.copyWith(crop: value));
  }

  Future<void> _editLyricBand(int index) async {
    final strip = _draft.strips[index];
    final value = await showDialog<NormalizedRect>(
      context: context,
      builder: (_) => RectEditorDialog(
        imagePath: widget.services.library.assetPath(
          strip.assetHash,
          strip.assetExtension,
        ),
        imageAspectRatio: strip.pixelWidth / strip.pixelHeight,
        title: 'Select original lyric area',
        initialRect:
            strip.lyricBand ?? const NormalizedRect(0.02, 0.70, 0.98, 0.98),
      ),
    );
    if (value != null) _replaceStrip(index, strip.copyWith(lyricBand: value));
  }

  Future<void> _addHighlight(int index) async {
    final strip = _draft.strips[index];
    final value = await showDialog<NormalizedRect>(
      context: context,
      builder: (_) => RectEditorDialog(
        imagePath: widget.services.library.assetPath(
          strip.assetHash,
          strip.assetExtension,
        ),
        imageAspectRatio: strip.pixelWidth / strip.pixelHeight,
        title: 'Highlight backing-vocal lyrics',
        initialRect:
            strip.lyricBand ?? const NormalizedRect(0.10, 0.76, 0.38, 0.94),
      ),
    );
    if (value == null) return;
    _replaceStrip(
      index,
      strip.copyWith(
        highlights: [
          ...strip.highlights,
          VisualHighlight(id: IdFactory.next('highlight'), rect: value),
        ],
      ),
    );
  }

  void _duplicate(int index) {
    final strip = _draft.strips[index];
    final duplicate = VisualStrip(
      id: IdFactory.next('strip'),
      assetHash: strip.assetHash,
      assetExtension: strip.assetExtension,
      pixelWidth: strip.pixelWidth,
      pixelHeight: strip.pixelHeight,
      sourceAssetHash: strip.sourceAssetHash,
      sourcePage: strip.sourcePage,
      crop: strip.crop,
      treatment: strip.treatment,
      lyricBand: strip.lyricBand,
      lyricContrast: strip.lyricContrast,
      highlights: strip.highlights,
    );
    final strips = [..._draft.strips]..insert(index + 1, duplicate);
    setState(() => _draft = _draft.copyWith(strips: strips));
  }

  void _delete(int index) {
    final strips = [..._draft.strips]..removeAt(index);
    setState(() => _draft = _draft.copyWith(strips: strips));
  }

  void _replaceStrip(int index, VisualStrip strip) {
    final strips = [..._draft.strips]..[index] = strip;
    setState(() => _draft = _draft.copyWith(strips: strips));
  }

  void _reorder(int oldIndex, int newIndex) {
    final strips = [..._draft.strips];
    final strip = strips.removeAt(oldIndex);
    strips.insert(newIndex, strip);
    setState(() => _draft = _draft.copyWith(strips: strips));
  }

  VisualChartDraft _withMetadata() {
    return _draft.copyWith(
      title: _titleController.text.trim().isEmpty
          ? 'Untitled chart'
          : _titleController.text.trim(),
      artist: _artistController.text.trim(),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _draft = _withMetadata();
    });
    try {
      await widget.services.library.saveDraft(_draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chart saved to Song Pool.')),
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _draft = _withMetadata();
    });
    try {
      await widget.services.library.saveDraft(_draft);
      final destination = await widget.services.exporter.exportWithPicker(
        _draft,
      );
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A4 PDF exported to $destination')),
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

enum _ImportKind { images, pdf, clipboard }

class _EmptyImportState extends StatelessWidget {
  const _EmptyImportState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.view_stream_outlined, size: 64),
          SizedBox(height: 12),
          Text('Add screenshots or a PDF to create horizontal tab rows.'),
          SizedBox(height: 4),
          Text(
            'Original files remain untouched. Crop and display edits are reversible.',
          ),
        ],
      ),
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({
    super.key,
    required this.index,
    required this.strip,
    required this.globalTreatment,
    required this.services,
    required this.onChanged,
    required this.onCrop,
    required this.onLyricBand,
    required this.onAddHighlight,
    required this.onDuplicate,
    required this.onDelete,
  });

  final int index;
  final VisualStrip strip;
  final VisualTreatment? globalTreatment;
  final AppServices services;
  final ValueChanged<VisualStrip> onChanged;
  final VoidCallback onCrop;
  final VoidCallback onLyricBand;
  final VoidCallback onAddHighlight;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
                Text('Row ${index + 1}'),
                if (strip.sourcePage case final page?) ...[
                  const SizedBox(width: 8),
                  Chip(label: Text('PDF page $page')),
                ],
                const Spacer(),
                DropdownButton<VisualTreatment>(
                  value: strip.treatment,
                  onChanged: globalTreatment != null
                      ? null
                      : (value) {
                          if (value != null) {
                            onChanged(strip.copyWith(treatment: value));
                          }
                        },
                  items: VisualTreatment.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(growable: false),
                ),
                IconButton(
                  tooltip: 'Duplicate row',
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: 'Delete row',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 90, maxHeight: 320),
              child: VisualStripPreview(
                library: services.library,
                strip: strip,
                globalTreatment: globalTreatment,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onCrop,
                  icon: const Icon(Icons.crop),
                  label: const Text('Crop row'),
                ),
                OutlinedButton.icon(
                  onPressed: onLyricBand,
                  icon: const Icon(Icons.subtitles_outlined),
                  label: Text(
                    strip.lyricBand == null
                        ? 'Select lyric area'
                        : 'Edit lyric area',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAddHighlight,
                  icon: const Icon(Icons.format_color_fill),
                  label: const Text('Highlight backing vocal'),
                ),
                if (strip.lyricBand != null) ...[
                  const Text('Lyric contrast'),
                  SizedBox(
                    width: 180,
                    child: Slider(
                      value: strip.lyricContrast,
                      min: 0.25,
                      max: 2,
                      divisions: 7,
                      label: '${strip.lyricContrast.toStringAsFixed(2)}x',
                      onChanged: (value) =>
                          onChanged(strip.copyWith(lyricContrast: value)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove lyric area',
                    onPressed: () => onChanged(
                      strip.copyWith(clearLyricBand: true, lyricContrast: 1),
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ],
                if (strip.highlights.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.layers_clear_outlined, size: 18),
                    label: Text(
                      'Clear ${strip.highlights.length} highlight(s)',
                    ),
                    onPressed: () =>
                        onChanged(strip.copyWith(highlights: const [])),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
