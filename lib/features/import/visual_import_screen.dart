import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/app_services.dart';
import '../../application/draft_edit_session.dart';
import '../../application/highlight_geometry.dart';
import '../../application/recognition_review.dart';
import '../../application/semantic_recognition_service.dart';
import '../../application/service_contracts.dart';
import '../../application/visual_tab_analysis_service.dart';
import '../../application/visual_tab_transform_service.dart';
import '../../domain/music_models.dart';
import '../../domain/visual_chart_models.dart';
import '../../domain/visual_tab_transform_models.dart';
import 'multi_row_split_dialog.dart';
import 'rect_editor_dialog.dart';
import 'text_highlighter_dialog.dart';
import 'visual_tab_analysis_dialog.dart';
import 'visual_tab_transform_dialog.dart';
import 'visual_strip_preview.dart';
import 'visual_deskew_dialog.dart';

class VisualImportScreen extends StatefulWidget {
  const VisualImportScreen({
    super.key,
    required this.services,
    this.initialDraft,
    this.onSemanticProposalCreated,
  });

  final AppServices services;
  final VisualChartDraft? initialDraft;
  final ValueChanged<SongChart>? onSemanticProposalCreated;

  @override
  State<VisualImportScreen> createState() => _VisualImportScreenState();
}

class _VisualImportScreenState extends State<VisualImportScreen> {
  late VisualChartDraft _draft;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final FocusNode _shortcutFocusNode;
  final ScrollController _editorScrollController = ScrollController();
  final DraftUndoHistory _undoHistory = DraftUndoHistory();
  late final DebouncedDraftAutosaver _autosaver;
  bool _busy = false;
  bool _dragging = false;
  bool _syncingMetadata = false;
  Object? _autosaveError;

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
    _titleController.addListener(_metadataChanged);
    _artistController.addListener(_metadataChanged);
    _autosaver = DebouncedDraftAutosaver(
      save: (draft) async {
        await widget.services.library.saveDraft(draft);
        if (mounted && _autosaveError != null) {
          setState(() => _autosaveError = null);
        }
      },
      onError: (error, _) {
        if (mounted) setState(() => _autosaveError = error);
      },
    );
    _shortcutFocusNode = FocusNode(debugLabel: 'Visual editor shortcuts');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shortcutFocusNode.requestFocus();
    });
  }

  void _metadataChanged() {
    if (_syncingMetadata) return;
    _commitDraft(_withMetadata());
  }

  void _commitDraft(VisualChartDraft next, {bool recordUndo = true}) {
    if (recordUndo) _undoHistory.record(_draft);
    setState(() {
      _draft = next;
      _autosaveError = null;
    });
    if (_draft.strips.isNotEmpty) _autosaver.schedule(_draft);
  }

  void _undo() {
    final previous = _undoHistory.undo();
    if (previous == null) return;
    final restored = previous.copyWith(updatedAt: DateTime.now().toUtc());
    _syncingMetadata = true;
    _titleController.text = restored.title;
    _artistController.text = restored.artist;
    _syncingMetadata = false;
    _commitDraft(restored, recordUndo: false);
  }

  Future<void> _recognizeSemanticProposal() async {
    if (_busy || _draft.strips.isEmpty) return;
    final settings = await _chooseRecognitionSettings();
    if (settings == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final inputs = <RecognitionStripInput>[];
      for (final strip in _draft.strips) {
        final recognition = await widget.services.textRecognition.recognize(
          strip,
        );
        inputs.add(
          RecognitionStripInput(
            sourceId: '${strip.assetHash}.${strip.assetExtension}',
            regions: recognition.regions,
            stringCount: settings.tuning.strings.length,
            tabBand: settings.combinedNotationAndTab
                ? const NormalizedRect(0, 0.5, 1, 0.99)
                : const NormalizedRect(0, 0.05, 1, 0.95),
          ),
        );
      }
      final chartId = 'semantic-${_draft.id}';
      final fresh = const SemanticRecognitionService().propose(
        chartId: chartId,
        title: _draft.title,
        artist: _draft.artist,
        strips: inputs,
        tuning: settings.tuning,
      );
      final prior = await widget.services.semanticCharts.loadSemanticChart(
        chartId,
      );
      final proposal = prior == null
          ? fresh.chart
          : mergeRecognitionRerun(prior, fresh.chart);
      final identity = await widget.services.songVariants.identityForDraft(
        _draft.id,
      );
      await widget.services.semanticCharts.saveSemanticChart(
        proposal,
        songId: identity?.songId ?? 'song-${_draft.id}',
        updatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      widget.onSemanticProposalCreated?.call(proposal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${fresh.proposedEvents} local recognition proposal(s). '
            '${fresh.diagnostics.length} row(s) need extra review.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Semantic recognition failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewVisualTabAnalysis({
    List<VisualStrip>? stripsOverride,
  }) async {
    final strips = stripsOverride ?? _draft.strips;
    if (_busy || strips.isEmpty) return;
    final sourceStringCount = await _chooseSourceStringCount();
    if (sourceStringCount == null || !mounted) return;
    final result = await showVisualTabAnalysisReview(
      context: context,
      library: widget.services.library,
      analyzer: VisualTabAnalysisService(
        library: widget.services.library,
        textRecognition: widget.services.textRecognition,
      ),
      strips: strips,
      sourceStringCount: sourceStringCount,
    );
    if (result == null || !mounted) return;
    final configuration = await showVisualTabTransformDialog(
      context: context,
      sourceStringCount: sourceStringCount,
    );
    if (configuration == null || !mounted) return;
    await _applyVisualTabTransform(result, configuration);
  }

  Future<void> _applyVisualTabTransform(
    List<VisualTabAnalysis> analyses,
    VisualTabTransformConfiguration configuration,
  ) async {
    setState(() => _busy = true);
    try {
      final transformed = await VisualTabTransformService(
        widget.services.library,
      ).apply(draft: _draft, analyses: analyses, configuration: configuration);
      if (!mounted) return;
      _commitDraft(transformed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transformed ${analyses.fold<int>(0, (total, item) => total + item.enabledFretTokenCount)} '
            'reviewed fret/dead-note token(s). Ctrl+Z restores the prior chart.',
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editOrRemoveVisualTransform() async {
    final record = _draft.visualTabTransform;
    if (record == null) {
      await _reviewVisualTabAnalysis();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit transform settings'),
              subtitle: const Text('Reapply from the immutable original rows.'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Review detections again'),
              subtitle: const Text(
                'Return to the original rows and rerun PDF/OCR analysis.',
              ),
              onTap: () => Navigator.pop(context, 'review'),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Remove visual transform'),
              subtitle: const Text('Restore all original visual rows.'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      final restored = VisualTabTransformService(
        widget.services.library,
      ).remove(_draft);
      _commitDraft(restored);
      return;
    }
    if (action == 'review') {
      await _reviewVisualTabAnalysis(stripsOverride: record.baseStrips);
      return;
    }
    final analyses = record.analyses
        .map(VisualTabAnalysis.fromJson)
        .toList(growable: false);
    final initial = VisualTabTransformConfiguration.fromJson(
      record.configuration,
    );
    final configuration = await showVisualTabTransformDialog(
      context: context,
      sourceStringCount: initial.sourceLabels.length,
      initialValue: initial,
    );
    if (configuration != null && mounted) {
      await _applyVisualTabTransform(analyses, configuration);
    }
  }

  Future<int?> _chooseSourceStringCount() async {
    final controller = TextEditingController(text: '4');
    String? error;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm source tab strings'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Source string count',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Music Tabbler will detect string lines and propose fret '
                  'tokens. It will not silently verify the source tuning.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 2 || value > 12) {
                  setDialogState(() => error = 'Enter 2 to 12 strings.');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Analyze'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<_RecognitionSettings?> _chooseRecognitionSettings() async {
    var tuning = BassTuning.eadg;
    var combinedNotationAndTab = true;
    return showDialog<_RecognitionSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Recognition source layout'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<BassTuning>(
                initialValue: tuning,
                decoration: const InputDecoration(
                  labelText: 'Original source tuning',
                ),
                items: const [
                  DropdownMenuItem(
                    value: BassTuning.eadg,
                    child: Text('4-string EADG'),
                  ),
                  DropdownMenuItem(
                    value: BassTuning.beadg,
                    child: Text('5-string BEADG'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => tuning = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                initialValue: combinedNotationAndTab,
                decoration: const InputDecoration(labelText: 'Row layout'),
                items: const [
                  DropdownMenuItem(
                    value: true,
                    child: Text('Notation above tablature'),
                  ),
                  DropdownMenuItem(value: false, child: Text('Tablature only')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => combinedNotationAndTab = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'Recognition creates editable proposals only. Review every '
                'note before using transpose or gig-ready.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _RecognitionSettings(
                  tuning: tuning,
                  combinedNotationAndTab: combinedNotationAndTab,
                ),
              ),
              child: const Text('Recognize'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.removeListener(_metadataChanged);
    _artistController.removeListener(_metadataChanged);
    unawaited(_autosaver.dispose());
    _titleController.dispose();
    _artistController.dispose();
    _shortcutFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteShortcut,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
      },
      child: Focus(
        focusNode: _shortcutFocusNode,
        autofocus: true,
        child: _DesktopDropRegion(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: _importDropped,
          child: Stack(
            children: [
              Scaffold(
                appBar: AppBar(
                  title: const Text('Visual chart editor'),
                  actions: [
                    IconButton(
                      tooltip: _draft.visualTabTransform == null
                          ? 'Analyze visual tab for transform'
                          : 'Edit or remove visual tab transform',
                      onPressed: _busy || _draft.strips.isEmpty
                          ? null
                          : _editOrRemoveVisualTransform,
                      icon: Icon(
                        _draft.visualTabTransform == null
                            ? Icons.alt_route
                            : Icons.transform,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Recognize semantic proposal',
                      onPressed: _busy || _draft.strips.isEmpty
                          ? null
                          : _recognizeSemanticProposal,
                      icon: const Icon(Icons.auto_fix_high),
                    ),
                    IconButton(
                      tooltip: _draft.provenance == null
                          ? 'Add source details'
                          : 'Source details',
                      onPressed: _busy ? null : _editProvenance,
                      icon: Icon(
                        _draft.provenance == null
                            ? Icons.link_outlined
                            : Icons.link,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Undo last edit (Ctrl+Z)',
                      onPressed: _undoHistory.canUndo ? _undo : null,
                      icon: const Icon(Icons.undo),
                    ),
                    if (_autosaveError != null)
                      const Tooltip(
                        message: 'Autosave failed; use Save to retry.',
                        child: Icon(Icons.cloud_off_outlined),
                      )
                    else
                      const Tooltip(
                        message: 'Edits autosave locally',
                        child: Icon(Icons.cloud_done_outlined),
                      ),
                    if (MediaQuery.sizeOf(context).width >= 700)
                      TextButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      )
                    else
                      IconButton(
                        tooltip: 'Save',
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                      ),
                    const SizedBox(width: 8),
                    if (MediaQuery.sizeOf(context).width >= 700)
                      FilledButton.icon(
                        onPressed: _busy || _draft.strips.isEmpty
                            ? null
                            : _export,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export A4'),
                      )
                    else
                      IconButton.filled(
                        tooltip: 'Export A4',
                        onPressed: _busy || _draft.strips.isEmpty
                            ? null
                            : _export,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                      ),
                    const SizedBox(width: 8),
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
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 850;
                                final fieldWidth = compact
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 12) / 2;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: TextField(
                                        controller: _titleController,
                                        decoration: const InputDecoration(
                                          labelText: 'Song title',
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.fromLTRB(
                                            14,
                                            20,
                                            14,
                                            16,
                                          ),
                                          constraints: BoxConstraints(
                                            minHeight: 60,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: TextField(
                                        controller: _artistController,
                                        decoration: const InputDecoration(
                                          labelText: 'Artist',
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.fromLTRB(
                                            14,
                                            20,
                                            14,
                                            16,
                                          ),
                                          constraints: BoxConstraints(
                                            minHeight: 60,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DropdownButton<VisualTreatment?>(
                                      value: _draft.globalTreatment,
                                      hint: const Text('Per-strip display'),
                                      onChanged: (value) => _commitDraft(
                                        value == null
                                            ? _draft.copyWith(
                                                clearGlobalTreatment: true,
                                              )
                                            : _draft.copyWith(
                                                globalTreatment: value,
                                              ),
                                      ),
                                      items: [
                                        const DropdownMenuItem<
                                          VisualTreatment?
                                        >(
                                          value: null,
                                          child: Text('Per-strip display'),
                                        ),
                                        ...VisualTreatment.values.map(
                                          (value) =>
                                              DropdownMenuItem<
                                                VisualTreatment?
                                              >(
                                                value: value,
                                                child: Text(
                                                  'Whole tab: ${value.label}',
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                    FilterChip(
                                      label: const Text(
                                        'Title / artist in PDF',
                                      ),
                                      selected: _draft.showHeader,
                                      onSelected: (value) => _commitDraft(
                                        _draft.copyWith(showHeader: value),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Tooltip(
                                  message: _draft.exportDensity.description,
                                  child: DropdownButton<VisualExportDensity>(
                                    value: _draft.exportDensity,
                                    onChanged: _busy
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              _commitDraft(
                                                _draft.copyWith(
                                                  exportDensity: value,
                                                ),
                                              );
                                            }
                                          },
                                    items: [
                                      for (final density
                                          in VisualExportDensity.values)
                                        DropdownMenuItem(
                                          value: density,
                                          child: Text(
                                            'PDF density: ${density.label}',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: _busy
                                      ? null
                                      : () => _add(_ImportKind.images),
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                  label: const Text('Add PNG / JPEG'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: _busy
                                      ? null
                                      : () => _add(_ImportKind.pdf),
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                  ),
                                  label: const Text('Add PDF'),
                                ),
                                if (defaultTargetPlatform ==
                                    TargetPlatform.windows)
                                  FilledButton.tonalIcon(
                                    onPressed: _busy
                                        ? null
                                        : () => _add(_ImportKind.clipboard),
                                    icon: const Icon(
                                      Icons.content_paste_outlined,
                                    ),
                                    label: const Text('Paste image (Ctrl+V)'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _busy || _draft.strips.isEmpty
                                      ? null
                                      : () => _recognizeMetadata(
                                          _draft.strips.first,
                                        ),
                                  icon: const Icon(
                                    Icons.auto_fix_high_outlined,
                                  ),
                                  label: const Text('Detect title / artist'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy || _draft.strips.isEmpty
                                      ? null
                                      : _openChartHighlighter,
                                  icon: const Icon(Icons.highlight_alt),
                                  label: const Text('Open chart highlighter'),
                                ),
                                if (_busy)
                                  const SizedBox.square(
                                    dimension: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              defaultTargetPlatform == TargetPlatform.windows
                                  ? 'You can also drag images, PDFs, or an entire screenshot folder anywhere into this editor.'
                                  : 'Use Add PNG / JPEG or Add PDF to choose files stored on this device.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _draft.strips.isEmpty
                          ? _EmptyImportState(sourceUrl: _draft.provenance?.url)
                          : Scrollbar(
                              controller: _editorScrollController,
                              thumbVisibility: true,
                              child: Listener(
                                onPointerSignal: (event) {
                                  if (event is! PointerScrollEvent ||
                                      !_editorScrollController.hasClients) {
                                    return;
                                  }
                                  GestureBinding.instance.pointerSignalResolver
                                      .register(event, (resolvedEvent) {
                                        final scroll =
                                            resolvedEvent as PointerScrollEvent;
                                        final position =
                                            _editorScrollController.position;
                                        _editorScrollController.jumpTo(
                                          (position.pixels +
                                                  scroll.scrollDelta.dy)
                                              .clamp(
                                                position.minScrollExtent,
                                                position.maxScrollExtent,
                                              ),
                                        );
                                      });
                                },
                                child: ReorderableListView.builder(
                                  scrollController: _editorScrollController,
                                  primary: false,
                                  physics: const ClampingScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _draft.strips.length,
                                  onReorderItem: _reorder,
                                  itemBuilder: (context, index) {
                                    final strip = _draft.strips[index];
                                    return _StripCard(
                                      key: ValueKey(strip.id),
                                      index: index,
                                      strip: strip,
                                      sourceLabel: _sourceLabelAt(index),
                                      globalTreatment: _draft.globalTreatment,
                                      services: widget.services,
                                      onChanged: (value) =>
                                          _replaceStrip(index, value),
                                      onSplit: () => _splitRow(index),
                                      onCrop: () => _editCrop(index),
                                      onDeskew: () => _editDeskew(index),
                                      onDuplicate: () => _duplicate(index),
                                      onDelete: () => _delete(index),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.20),
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'Drop images, PDFs, or screenshot folders',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(_ImportKind kind) async {
    setState(() => _busy = true);
    try {
      final additions = switch (kind) {
        _ImportKind.images => await widget.services.importer.pickImages(),
        _ImportKind.pdf => await widget.services.importer.pickPdf(),
        _ImportKind.clipboard => await widget.services.importer.pasteImages(),
      };
      if (!mounted) return;
      _appendRows(additions);
    } on ImportCancelled {
      // Native picker cancellation is not an error.
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sourceLabelAt(int stripIndex) {
    final strip = _draft.strips[stripIndex];
    if (strip.sourcePage case final page?) return 'PDF page $page';
    final imageHashes = <String>[];
    for (final candidate in _draft.strips) {
      if (candidate.sourcePage != null) continue;
      if (!imageHashes.contains(candidate.assetHash)) {
        imageHashes.add(candidate.assetHash);
      }
    }
    return 'Image source ${imageHashes.indexOf(strip.assetHash) + 1}';
  }

  void _pasteShortcut() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    if (!_busy) unawaited(_add(_ImportKind.clipboard));
  }

  Future<void> _importDropped(DropDoneDetails details) async {
    setState(() {
      _dragging = false;
      _busy = true;
    });
    try {
      final additions = await widget.services.importer.importPaths(
        details.files.map((item) => item.path),
      );
      if (mounted) _appendRows(additions);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _appendRows(List<VisualStrip> additions) {
    if (additions.isEmpty) return;
    final shouldRecognize =
        _draft.strips.isEmpty &&
        (_titleController.text.trim().isEmpty ||
            _titleController.text.trim() == 'Untitled chart');
    _commitDraft(_draft.copyWith(strips: [..._draft.strips, ...additions]));
    if (shouldRecognize) unawaited(_recognizeMetadata(additions.first));
  }

  Future<void> _recognizeMetadata(VisualStrip strip) async {
    try {
      final sourceStrip = strip.copyWith(crop: const NormalizedRect.full());
      final suggestion = await widget.services.textRecognition.recognize(
        sourceStrip,
      );
      if (!mounted) return;
      _syncingMetadata = true;
      if (suggestion.title case final title? when title.trim().isNotEmpty) {
        _titleController.text = title.trim();
      }
      if (suggestion.artist case final artist? when artist.trim().isNotEmpty) {
        _artistController.text = artist.trim();
      }
      _syncingMetadata = false;
      _commitDraft(_withMetadata());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Title and artist were read locally. Check them before export.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The chart was imported, but title/artist recognition was unsure: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _splitRow(int index) async {
    final strip = _draft.strips[index];
    final siblingIndexes = <int>[
      for (
        var candidateIndex = 0;
        candidateIndex < _draft.strips.length;
        candidateIndex += 1
      )
        if (_sameSourcePage(_draft.strips[candidateIndex], strip))
          candidateIndex,
    ];
    final siblings = [
      for (final siblingIndex in siblingIndexes) _draft.strips[siblingIndex],
    ];
    final rows = await showDialog<List<NormalizedRect>>(
      context: context,
      builder: (_) => MultiRowSplitDialog(
        imagePath: widget.services.library.assetPath(
          strip.assetHash,
          strip.assetExtension,
        ),
        imageAspectRatio: strip.deskewedPixelWidth / strip.deskewedPixelHeight,
        sourceRect: const NormalizedRect.full(),
        initialRows: [for (final sibling in siblings) sibling.crop],
        deskewDegrees: strip.deskewDegrees,
      ),
    );
    if (rows == null || rows.isEmpty) return;
    final replacements = [
      for (final crop in rows) _resplitStrip(crop, siblings),
    ];
    final insertAt = siblingIndexes.first;
    final siblingSet = siblingIndexes.toSet();
    final strips = <VisualStrip>[];
    for (
      var candidateIndex = 0;
      candidateIndex < _draft.strips.length;
      candidateIndex += 1
    ) {
      if (candidateIndex == insertAt) strips.addAll(replacements);
      if (!siblingSet.contains(candidateIndex)) {
        strips.add(_draft.strips[candidateIndex]);
      }
    }
    _commitDraft(_draft.copyWith(strips: strips));
  }

  bool _sameSourcePage(VisualStrip left, VisualStrip right) =>
      left.assetHash == right.assetHash &&
      left.sourcePage == right.sourcePage &&
      (left.deskewDegrees - right.deskewDegrees).abs() < 0.0001;

  VisualStrip _resplitStrip(NormalizedRect crop, List<VisualStrip> siblings) {
    final template = siblings.reduce((best, candidate) {
      final bestOverlap = _verticalOverlap(best.crop, crop);
      final candidateOverlap = _verticalOverlap(candidate.crop, crop);
      return candidateOverlap > bestOverlap ? candidate : best;
    });
    final highlights = <VisualHighlight>[
      for (final sibling in siblings)
        for (final highlight in sibling.highlights)
          if (_rectsIntersect(highlight.rect, crop)) highlight,
    ];
    return VisualStrip(
      id: IdFactory.next('strip'),
      assetHash: template.assetHash,
      assetExtension: template.assetExtension,
      pixelWidth: template.pixelWidth,
      pixelHeight: template.pixelHeight,
      sourceAssetHash: template.sourceAssetHash,
      sourcePage: template.sourcePage,
      crop: crop,
      treatment: template.treatment,
      lyricBand: template.lyricBand,
      lyricContrast: template.lyricContrast,
      highlights: highlights,
      deskewDegrees: template.deskewDegrees,
    );
  }

  double _verticalOverlap(NormalizedRect left, NormalizedRect right) {
    final top = left.top > right.top ? left.top : right.top;
    final bottom = left.bottom < right.bottom ? left.bottom : right.bottom;
    return (bottom - top).clamp(0.0, 1.0);
  }

  bool _rectsIntersect(NormalizedRect left, NormalizedRect right) =>
      left.left < right.right &&
      left.right > right.left &&
      left.top < right.bottom &&
      left.bottom > right.top;

  Future<void> _editCrop(int index) async {
    final strip = _draft.strips[index];
    final value = await showDialog<NormalizedRect>(
      context: context,
      builder: (_) => RectEditorDialog(
        imagePath: widget.services.library.assetPath(
          strip.assetHash,
          strip.assetExtension,
        ),
        imageAspectRatio: strip.croppedAspectRatio,
        title: 'Crop tab row',
        initialRect: const NormalizedRect.full(),
        viewportRect: strip.crop,
        deskewDegrees: strip.deskewDegrees,
      ),
    );
    if (value != null) {
      _replaceStrip(
        index,
        strip.copyWith(crop: cropLocalRectToAsset(value, strip.crop)),
      );
    }
  }

  Future<void> _editDeskew(int index) async {
    final strip = _draft.strips[index];
    final value = await showDialog<VisualStrip>(
      context: context,
      builder: (_) => VisualDeskewDialog(
        library: widget.services.library,
        strip: strip,
        globalTreatment: _draft.globalTreatment,
      ),
    );
    if (value != null) _replaceStrip(index, value);
    // Dialog controls can retain the primary focus on Windows after closing,
    // which prevents the editor-level Ctrl+Z shortcut from seeing the key.
    _shortcutFocusNode.requestFocus();
  }

  Future<void> _openChartHighlighter() async {
    final selection = await showDialog<TextHighlightSelection>(
      context: context,
      builder: (_) => TextHighlighterDialog(
        strips: _draft.strips,
        library: widget.services.library,
        textRecognition: widget.services.textRecognition,
        globalTreatment: _draft.globalTreatment,
      ),
    );
    if (selection == null) return;
    final strips = [
      for (final strip in _draft.strips)
        strip.copyWith(
          clearLyricBand: true,
          lyricContrast: 1,
          highlights: [
            for (final localRect
                in selection.rectsByStrip[strip.id] ?? const [])
              VisualHighlight(
                id: IdFactory.next('highlight'),
                rect: cropLocalRectToAsset(localRect, strip.crop),
              ),
          ],
        ),
    ];
    _commitDraft(_draft.copyWith(strips: strips));
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
      annotations: strip.annotations,
      annotationsVisible: strip.annotationsVisible,
      includeAnnotationsInPdf: strip.includeAnnotationsInPdf,
    );
    final strips = [..._draft.strips]..insert(index + 1, duplicate);
    _commitDraft(_draft.copyWith(strips: strips));
  }

  void _delete(int index) {
    final strips = [..._draft.strips]..removeAt(index);
    _commitDraft(_draft.copyWith(strips: strips));
  }

  void _replaceStrip(int index, VisualStrip strip) {
    final strips = [..._draft.strips]..[index] = strip;
    _commitDraft(_draft.copyWith(strips: strips));
  }

  void _reorder(int oldIndex, int newIndex) {
    final strips = [..._draft.strips];
    final strip = strips.removeAt(oldIndex);
    strips.insert(newIndex, strip);
    _commitDraft(_draft.copyWith(strips: strips));
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
    setState(() => _busy = true);
    try {
      _autosaver.schedule(_draft);
      await _autosaver.flush();
      if (_autosaveError case final error?) throw error;
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

  Future<void> _editProvenance() async {
    final current = _draft.provenance;
    final url = TextEditingController(text: current?.url ?? '');
    final provider = TextEditingController(text: current?.provider ?? '');
    final version = TextEditingController(text: current?.versionName ?? '');
    final notes = TextEditingController(text: current?.notes ?? '');
    var method = current?.importMethod ?? ProvenanceImportMethod.screenshot;
    String? validation;
    final result = await showDialog<_ProvenanceDialogResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Source details'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Source URL',
                      errorText: validation,
                    ),
                  ),
                  TextField(
                    controller: provider,
                    decoration: const InputDecoration(
                      labelText: 'Provider / site',
                    ),
                  ),
                  TextField(
                    controller: version,
                    decoration: const InputDecoration(
                      labelText: 'Version or source name',
                    ),
                  ),
                  DropdownButtonFormField<ProvenanceImportMethod>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Imported as'),
                    items: const [
                      DropdownMenuItem(
                        value: ProvenanceImportMethod.screenshot,
                        child: Text('Screenshots / images'),
                      ),
                      DropdownMenuItem(
                        value: ProvenanceImportMethod.pdf,
                        child: Text('PDF'),
                      ),
                      DropdownMenuItem(
                        value: ProvenanceImportMethod.other,
                        child: Text('Other manual import'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => method = value);
                      }
                    },
                  ),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  const _ProvenanceDialogResult(remove: true),
                ),
                child: const Text('Remove'),
              ),
            if (current != null) ...[
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: current.url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Source URL copied.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy URL'),
              ),
              if (widget.services.externalUrlOpener != null)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await widget.services.externalUrlOpener!.open(
                        current.url,
                      );
                    } catch (error) {
                      if (context.mounted) _showError(error);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final normalized = normalizeSourceUrl(url.text);
                  Navigator.pop(
                    context,
                    _ProvenanceDialogResult(
                      value: SourceProvenance(
                        url: normalized,
                        provider: provider.text.trim().isEmpty
                            ? inferSourceProvider(normalized)
                            : provider.text.trim(),
                        versionName: version.text.trim(),
                        importMethod: method,
                        notes: notes.text.trim(),
                      ),
                    ),
                  );
                } on FormatException catch (error) {
                  setDialogState(() => validation = error.message);
                }
              },
              child: const Text('Save source'),
            ),
          ],
        ),
      ),
    );
    url.dispose();
    provider.dispose();
    version.dispose();
    notes.dispose();
    if (result == null) return;
    _commitDraft(
      result.remove
          ? _draft.copyWith(clearProvenance: true)
          : _draft.copyWith(provenance: result.value),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      _autosaver.schedule(_draft);
      await _autosaver.flush();
      if (_autosaveError case final error?) throw error;
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

class _ProvenanceDialogResult {
  const _ProvenanceDialogResult({this.value, this.remove = false});

  final SourceProvenance? value;
  final bool remove;
}

class _EmptyImportState extends StatelessWidget {
  const _EmptyImportState({this.sourceUrl});

  final String? sourceUrl;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_stream_outlined, size: 48),
            const SizedBox(height: 8),
            if (sourceUrl != null) ...[
              const Text(
                'The link is saved as source information only.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Music Tabbler does not download or scrape Songsterr. '
                'Use Add PNG / JPEG, Add PDF, or Ctrl+V to attach the tab.',
                textAlign: TextAlign.center,
              ),
            ] else
              const Text(
                'Add screenshots or a PDF to create horizontal tab rows.',
              ),
            const SizedBox(height: 4),
            const Text(
              'Original files remain untouched. Crop and display edits are reversible.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({
    super.key,
    required this.index,
    required this.strip,
    required this.sourceLabel,
    required this.globalTreatment,
    required this.services,
    required this.onChanged,
    required this.onSplit,
    required this.onCrop,
    required this.onDeskew,
    required this.onDuplicate,
    required this.onDelete,
  });

  final int index;
  final VisualStrip strip;
  final String sourceLabel;
  final VisualTreatment? globalTreatment;
  final AppServices services;
  final ValueChanged<VisualStrip> onChanged;
  final VoidCallback onSplit;
  final VoidCallback onCrop;
  final VoidCallback onDeskew;
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
                const SizedBox(width: 8),
                Chip(label: Text(sourceLabel)),
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
                FilledButton.tonalIcon(
                  onPressed: strip.deskewDegrees.abs() < 0.0001
                      ? onSplit
                      : null,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Split into rows'),
                ),
                OutlinedButton.icon(
                  onPressed: strip.deskewDegrees.abs() < 0.0001 ? onCrop : null,
                  icon: const Icon(Icons.crop),
                  label: const Text('Crop row'),
                ),
                OutlinedButton.icon(
                  onPressed: onDeskew,
                  icon: const Icon(Icons.rotate_left),
                  label: Text(
                    strip.deskewDegrees.abs() < 0.0001
                        ? 'Deskew'
                        : 'Deskew ${strip.deskewDegrees.toStringAsFixed(1)}°',
                  ),
                ),
                if (strip.deskewDegrees.abs() >= 0.0001)
                  const Text(
                    'Reset deskew before splitting or cropping again.',
                  ),
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

class _RecognitionSettings {
  const _RecognitionSettings({
    required this.tuning,
    required this.combinedNotationAndTab,
  });

  final BassTuning tuning;
  final bool combinedNotationAndTab;
}

class _DesktopDropRegion extends StatelessWidget {
  const _DesktopDropRegion({
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragDone,
    required this.child,
  });

  final ValueChanged<DropEventDetails> onDragEntered;
  final ValueChanged<DropEventDetails> onDragExited;
  final ValueChanged<DropDoneDetails> onDragDone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) return child;
    return DropTarget(
      onDragEntered: onDragEntered,
      onDragExited: onDragExited,
      onDragDone: onDragDone,
      child: child,
    );
  }
}
