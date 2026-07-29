import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/service_contracts.dart';
import '../../application/visual_image_processor.dart';
import '../../application/visual_tab_analysis_service.dart';
import '../../domain/visual_chart_models.dart';
import '../../domain/visual_tab_transform_models.dart';

Future<List<VisualTabAnalysis>?> showVisualTabAnalysisReview({
  required BuildContext context,
  required ChartLibrary library,
  required VisualTabAnalysisService analyzer,
  required List<VisualStrip> strips,
  required int sourceStringCount,
}) {
  return Navigator.of(context).push<List<VisualTabAnalysis>>(
    MaterialPageRoute<List<VisualTabAnalysis>>(
      fullscreenDialog: true,
      builder: (context) => _VisualTabAnalysisReviewScreen(
        library: library,
        analyzer: analyzer,
        strips: strips,
        sourceStringCount: sourceStringCount,
      ),
    ),
  );
}

class _VisualTabAnalysisReviewScreen extends StatefulWidget {
  const _VisualTabAnalysisReviewScreen({
    required this.library,
    required this.analyzer,
    required this.strips,
    required this.sourceStringCount,
  });

  final ChartLibrary library;
  final VisualTabAnalysisService analyzer;
  final List<VisualStrip> strips;
  final int sourceStringCount;

  @override
  State<_VisualTabAnalysisReviewScreen> createState() =>
      _VisualTabAnalysisReviewScreenState();
}

class _VisualTabAnalysisReviewScreenState
    extends State<_VisualTabAnalysisReviewScreen> {
  final List<VisualTabAnalysis> _analyses = [];
  final Set<String> _selectedTokenIds = {};
  var _currentIndex = 0;
  var _processed = 0;
  Object? _error;
  bool _rerunningSource = false;
  bool _drawing = false;
  Offset? _drawStart;
  Offset? _drawEnd;

  VisualStrip get _strip => widget.strips[_currentIndex];
  VisualTabAnalysis get _analysis => _analyses[_currentIndex];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _run();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    Navigator.maybePop(context);
    return true;
  }

  Future<void> _run() async {
    try {
      final analyses = <VisualTabAnalysis>[];
      for (final strip in widget.strips) {
        analyses.add(
          await widget.analyzer.analyze(
            strip,
            sourceStringCount: widget.sourceStringCount,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _analyses.addAll(analyses);
        _processed = analyses.length;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = _processed == widget.strips.length && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review visual tab analysis'),
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          if (_analyses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('${_currentIndex + 1} / ${widget.strips.length}'),
              ),
            ),
          FilledButton.icon(
            onPressed: complete
                ? () => Navigator.pop(
                    context,
                    List<VisualTabAnalysis>.unmodifiable(_analyses),
                  )
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Use reviewed analysis'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _buildBody(complete),
    );
  }

  Widget _buildBody(bool complete) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Visual tab analysis failed: $_error'),
        ),
      );
    }
    if (_analyses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (!complete)
          LinearProgressIndicator(
            value: widget.strips.isEmpty
                ? null
                : _processed / widget.strips.length,
          ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  value: _currentIndex,
                  items: [
                    for (var index = 0; index < _analyses.length; index += 1)
                      DropdownMenuItem(
                        value: index,
                        child: Text('Row ${index + 1}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _currentIndex = value;
                      _selectedTokenIds.clear();
                    });
                  },
                ),
                Chip(
                  avatar: Icon(
                    _analysis.sourceType == VisualTabSourceType.positionedPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.document_scanner_outlined,
                  ),
                  label: Text(
                    _analysis.sourceType == VisualTabSourceType.positionedPdf
                        ? 'Positioned PDF text'
                        : 'Raster / OCR',
                  ),
                ),
                Text(
                  '${_analysis.systems.length} system(s), '
                  '${_analysis.enabledFretTokenCount} fret/dead-note token(s)',
                ),
                OutlinedButton.icon(
                  onPressed: _rerunningSource ? null : _rerunCurrentWithOcr,
                  icon: _rerunningSource
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_outlined),
                  label: const Text('Use raster / OCR'),
                ),
                FilterChip(
                  selected: _drawing,
                  avatar: const Icon(Icons.add_box_outlined),
                  label: const Text('Draw missing token'),
                  onSelected: (value) => setState(() => _drawing = value),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedTokenIds.length == 1
                      ? _editSelected
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedTokenIds.length > 1
                      ? _mergeSelected
                      : null,
                  icon: const Icon(Icons.call_merge),
                  label: const Text('Merge'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedTokenIds.length == 1
                      ? _splitSelected
                      : null,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Separate'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedTokenIds.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: _AnalysisCanvas(
                      library: widget.library,
                      strip: _strip,
                      analysis: _analysis,
                      selectedTokenIds: _selectedTokenIds,
                      drawing: _drawing,
                      drawStart: _drawStart,
                      drawEnd: _drawEnd,
                      onTokenTap: _toggleToken,
                      onDrawStart: (position) {
                        setState(() {
                          _drawStart = position;
                          _drawEnd = position;
                        });
                      },
                      onDrawUpdate: (position) =>
                          setState(() => _drawEnd = position),
                      onDrawEnd: _finishDraw,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 330,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (_analysis.warnings.isNotEmpty) ...[
                        for (final warning in _analysis.warnings)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.warning_amber_outlined),
                            title: Text(warning),
                          ),
                        const Divider(),
                      ],
                      for (final system in _analysis.systems) ...[
                        ListTile(
                          dense: true,
                          title: Text(
                            'System ${_analysis.systems.indexOf(system) + 1}',
                          ),
                          subtitle: Text(
                            '${system.stringLines.length} strings · '
                            '${system.barLines.length} bar lines · '
                            '${system.connectedNotationRisks.length} seam risk(s)',
                          ),
                        ),
                        for (final risk in system.connectedNotationRisks)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child:
                                DropdownButtonFormField<
                                  VisualConnectedComponentSide
                                >(
                                  initialValue: risk.side,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText:
                                        'Gap ${risk.gapIndex + 1} component',
                                    helperText:
                                        'Choose which side moves as one piece.',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: VisualConnectedComponentSide
                                          .unresolved,
                                      child: Text('Needs review'),
                                    ),
                                    DropdownMenuItem(
                                      value: VisualConnectedComponentSide.upper,
                                      child: Text('Move with upper string'),
                                    ),
                                    DropdownMenuItem(
                                      value: VisualConnectedComponentSide.lower,
                                      child: Text('Move with lower string'),
                                    ),
                                  ],
                                  onChanged: (side) {
                                    if (side != null) {
                                      _setRiskSide(system.id, risk.id, side);
                                    }
                                  },
                                ),
                          ),
                        for (final token in system.tokens)
                          CheckboxListTile(
                            dense: true,
                            value: _selectedTokenIds.contains(token.id),
                            onChanged: (_) => _toggleToken(token.id),
                            secondary: Icon(
                              token.enabled
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            title: Text(
                              token.text,
                              style: TextStyle(
                                decoration: token.enabled
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            subtitle: Text(
                              '${token.kind.name} · '
                              '${token.stringIndex == null ? "no string" : "string ${token.stringIndex! + 1}"}',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _rerunCurrentWithOcr() async {
    setState(() {
      _rerunningSource = true;
      _selectedTokenIds.clear();
    });
    try {
      final analysis = await widget.analyzer.analyze(
        _strip,
        sourceStringCount: widget.sourceStringCount,
        preferPositionedPdf: false,
      );
      if (!mounted) return;
      setState(() => _analyses[_currentIndex] = analysis);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Raster / OCR analysis failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _rerunningSource = false);
    }
  }

  void _toggleToken(String id) {
    setState(() {
      if (!_selectedTokenIds.add(id)) _selectedTokenIds.remove(id);
    });
  }

  void _setRiskSide(
    String systemId,
    String riskId,
    VisualConnectedComponentSide side,
  ) {
    setState(() {
      final systems = [
        for (final system in _analysis.systems)
          if (system.id != systemId)
            system
          else
            system.copyWith(
              connectedNotationRisks: [
                for (final risk in system.connectedNotationRisks)
                  if (risk.id == riskId) risk.copyWith(side: side) else risk,
              ],
            ),
      ];
      _analyses[_currentIndex] = _analysis.copyWith(systems: systems);
    });
  }

  VisualTabToken? _selectedToken() {
    if (_selectedTokenIds.length != 1) return null;
    final id = _selectedTokenIds.single;
    for (final system in _analysis.systems) {
      for (final token in system.tokens) {
        if (token.id == id) return token;
      }
    }
    return null;
  }

  Future<void> _editSelected() async {
    final token = _selectedToken();
    if (token == null) return;
    final result = await _editTokenDialog(token);
    if (result == null) return;
    _replaceToken(token.id, result);
  }

  Future<void> _mergeSelected() async {
    final selected = <VisualTabToken>[];
    for (final system in _analysis.systems) {
      selected.addAll(
        system.tokens.where((token) => _selectedTokenIds.contains(token.id)),
      );
    }
    if (selected.length < 2) return;
    selected.sort((left, right) => left.rect.left.compareTo(right.rect.left));
    final firstString = selected.first.stringIndex;
    if (selected.any((token) => token.stringIndex != firstString)) {
      _message('Merge tokens only when they belong to the same string.');
      return;
    }
    final merged = VisualTabToken(
      id: 'review_${DateTime.now().microsecondsSinceEpoch}',
      text: selected.map((token) => token.text).join(),
      rect: _boundingRect(selected.map((token) => token.rect)),
      kind: selected.every((token) => token.kind == VisualTabTokenKind.fret)
          ? VisualTabTokenKind.fret
          : VisualTabTokenKind.ambiguous,
      stringIndex: firstString,
      confidence:
          selected.map((token) => token.confidence).reduce(math.min) * 0.95,
    );
    _removeTokens(_selectedTokenIds);
    _addTokenToNearestSystem(merged);
  }

  Future<void> _splitSelected() async {
    final token = _selectedToken();
    if (token == null) return;
    final controller = TextEditingController(
      text: token.text.split('').join(','),
    );
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Separate OCR fragments'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Comma-separated token values',
            helperText: 'Example: 1, 2',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parts = controller.text
                  .split(',')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList();
              Navigator.pop(context, parts.length > 1 ? parts : null);
            },
            child: const Text('Separate'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (values == null || values.length < 2) return;
    _removeTokens({token.id});
    final width = token.rect.width / values.length;
    for (var index = 0; index < values.length; index += 1) {
      final part = token.copyWith(
        text: values[index],
        rect: NormalizedRect(
          token.rect.left + width * index,
          token.rect.top,
          token.rect.left + width * (index + 1),
          token.rect.bottom,
        ),
        kind: _kindForEditedValue(values[index], token.stringIndex),
      );
      _addTokenToNearestSystem(
        VisualTabToken(
          id: 'review_${DateTime.now().microsecondsSinceEpoch}_$index',
          text: part.text,
          rect: part.rect,
          kind: part.kind,
          stringIndex: part.stringIndex,
          confidence: part.confidence * 0.9,
          enabled: part.enabled,
        ),
      );
    }
  }

  void _deleteSelected() => _removeTokens(_selectedTokenIds);

  void _removeTokens(Set<String> ids) {
    final systems = [
      for (final system in _analysis.systems)
        system.copyWith(
          tokens: system.tokens
              .where((token) => !ids.contains(token.id))
              .toList(),
        ),
    ];
    setState(() {
      _analyses[_currentIndex] = _analysis.copyWith(systems: systems);
      _selectedTokenIds.clear();
    });
  }

  void _replaceToken(String id, VisualTabToken replacement) {
    final systems = [
      for (final system in _analysis.systems)
        system.copyWith(
          tokens: [
            for (final token in system.tokens)
              if (token.id == id) replacement else token,
          ],
        ),
    ];
    setState(() {
      _analyses[_currentIndex] = _analysis.copyWith(systems: systems);
      _selectedTokenIds
        ..clear()
        ..add(replacement.id);
    });
  }

  Future<void> _finishDraw(NormalizedRect? rect) async {
    if (rect == null || rect.width < 0.002 || rect.height < 0.002) {
      setState(() {
        _drawStart = null;
        _drawEnd = null;
      });
      return;
    }
    final nearest = _nearestString(rect);
    final provisional = VisualTabToken(
      id: 'review_${DateTime.now().microsecondsSinceEpoch}',
      text: '',
      rect: rect,
      kind: VisualTabTokenKind.ambiguous,
      stringIndex: nearest,
      confidence: 1,
    );
    final edited = await _editTokenDialog(provisional);
    if (!mounted) return;
    setState(() {
      _drawStart = null;
      _drawEnd = null;
      _drawing = false;
    });
    if (edited != null) _addTokenToNearestSystem(edited);
  }

  int? _nearestString(NormalizedRect rect) {
    final centerY = (rect.top + rect.bottom) / 2;
    int? nearest;
    var distance = double.infinity;
    for (final system in _analysis.systems) {
      for (var index = 0; index < system.stringLines.length; index += 1) {
        final next = (system.stringLines[index] - centerY).abs();
        if (next < distance) {
          distance = next;
          nearest = index;
        }
      }
    }
    return nearest;
  }

  void _addTokenToNearestSystem(VisualTabToken token) {
    if (_analysis.systems.isEmpty) return;
    final centerY = (token.rect.top + token.rect.bottom) / 2;
    var nearestIndex = 0;
    var distance = double.infinity;
    for (var index = 0; index < _analysis.systems.length; index += 1) {
      final rect = _analysis.systems[index].rect;
      final next = centerY < rect.top
          ? rect.top - centerY
          : centerY > rect.bottom
          ? centerY - rect.bottom
          : 0.0;
      if (next < distance) {
        distance = next;
        nearestIndex = index;
      }
    }
    final systems = [..._analysis.systems];
    systems[nearestIndex] = systems[nearestIndex].copyWith(
      tokens: [...systems[nearestIndex].tokens, token],
    );
    setState(() {
      _analyses[_currentIndex] = _analysis.copyWith(systems: systems);
      _selectedTokenIds
        ..clear()
        ..add(token.id);
    });
  }

  Future<VisualTabToken?> _editTokenDialog(VisualTabToken token) async {
    final text = TextEditingController(text: token.text);
    int? stringIndex = token.stringIndex;
    var enabled = token.enabled;
    final result = await showDialog<VisualTabToken>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review detected token'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Fret, (fret), X, or label',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: stringIndex,
                decoration: const InputDecoration(labelText: 'Source string'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Not a fret token'),
                  ),
                  for (
                    var index = 0;
                    index < widget.sourceStringCount;
                    index += 1
                  )
                    DropdownMenuItem<int?>(
                      value: index,
                      child: Text('String ${index + 1} (low to high)'),
                    ),
                ],
                onChanged: (value) => setDialogState(() => stringIndex = value),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: (value) =>
                    setDialogState(() => enabled = value ?? true),
                title: const Text('Use this detection'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = text.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(
                  context,
                  token.copyWith(
                    text: value,
                    kind: _kindForEditedValue(value, stringIndex),
                    stringIndex: stringIndex,
                    clearStringIndex: stringIndex == null,
                    confidence: 1,
                    enabled: enabled,
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    return result;
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

VisualTabTokenKind _kindForEditedValue(String value, int? stringIndex) {
  if (stringIndex == null) {
    return RegExp(r'^\d+$').hasMatch(value)
        ? VisualTabTokenKind.measureNumber
        : VisualTabTokenKind.ambiguous;
  }
  if (value.toUpperCase() == 'X') return VisualTabTokenKind.deadNote;
  return RegExp(r'^(?:\(\d{1,2}\)|\d{1,2})$').hasMatch(value)
      ? VisualTabTokenKind.fret
      : VisualTabTokenKind.ambiguous;
}

NormalizedRect _boundingRect(Iterable<NormalizedRect> rects) {
  var left = 1.0;
  var top = 1.0;
  var right = 0.0;
  var bottom = 0.0;
  for (final rect in rects) {
    left = math.min(left, rect.left);
    top = math.min(top, rect.top);
    right = math.max(right, rect.right);
    bottom = math.max(bottom, rect.bottom);
  }
  return NormalizedRect(left, top, right, bottom);
}

class _AnalysisCanvas extends StatefulWidget {
  const _AnalysisCanvas({
    required this.library,
    required this.strip,
    required this.analysis,
    required this.selectedTokenIds,
    required this.drawing,
    required this.drawStart,
    required this.drawEnd,
    required this.onTokenTap,
    required this.onDrawStart,
    required this.onDrawUpdate,
    required this.onDrawEnd,
  });

  final ChartLibrary library;
  final VisualStrip strip;
  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final bool drawing;
  final Offset? drawStart;
  final Offset? drawEnd;
  final ValueChanged<String> onTokenTap;
  final ValueChanged<Offset> onDrawStart;
  final ValueChanged<Offset> onDrawUpdate;
  final ValueChanged<NormalizedRect?> onDrawEnd;

  @override
  State<_AnalysisCanvas> createState() => _AnalysisCanvasState();
}

class _AnalysisCanvasState extends State<_AnalysisCanvas> {
  late Future<Uint8List> _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AnalysisCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strip.id != widget.strip.id) _load();
  }

  void _load() {
    _preview =
        File(
          widget.library.assetPath(
            widget.strip.assetHash,
            widget.strip.assetExtension,
          ),
        ).readAsBytes().then(
          (bytes) => compute(_renderAnalysisPreview, {
            'bytes': bytes,
            'strip': widget.strip.toJson(),
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _preview,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Preview unavailable'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return AspectRatio(
          aspectRatio: widget.strip.croppedAspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              Offset normalize(Offset local) => Offset(
                (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.drawing
                    ? (details) =>
                          widget.onDrawStart(normalize(details.localPosition))
                    : null,
                onPanUpdate: widget.drawing
                    ? (details) =>
                          widget.onDrawUpdate(normalize(details.localPosition))
                    : null,
                onPanEnd: widget.drawing
                    ? (_) {
                        final start = widget.drawStart;
                        final end = widget.drawEnd;
                        if (start == null || end == null) {
                          widget.onDrawEnd(null);
                          return;
                        }
                        final left = math.min(start.dx, end.dx);
                        final top = math.min(start.dy, end.dy);
                        final right = math.max(start.dx, end.dx);
                        final bottom = math.max(start.dy, end.dy);
                        widget.onDrawEnd(
                          right > left && bottom > top
                              ? NormalizedRect(left, top, right, bottom)
                              : null,
                        );
                      }
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(snapshot.data!, fit: BoxFit.fill),
                    CustomPaint(
                      painter: _AnalysisOverlayPainter(
                        analysis: widget.analysis,
                        selectedTokenIds: widget.selectedTokenIds,
                        drawStart: widget.drawStart,
                        drawEnd: widget.drawEnd,
                      ),
                    ),
                    for (final system in widget.analysis.systems)
                      for (final token in system.tokens)
                        Positioned(
                          left: token.rect.left * constraints.maxWidth,
                          top: token.rect.top * constraints.maxHeight,
                          width: token.rect.width * constraints.maxWidth,
                          height: token.rect.height * constraints.maxHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: widget.drawing
                                ? null
                                : () => widget.onTokenTap(token.id),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AnalysisOverlayPainter extends CustomPainter {
  const _AnalysisOverlayPainter({
    required this.analysis,
    required this.selectedTokenIds,
    required this.drawStart,
    required this.drawEnd,
  });

  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final Offset? drawStart;
  final Offset? drawEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.lightBlueAccent.withValues(alpha: 0.72)
      ..strokeWidth = 1.4;
    for (final system in analysis.systems) {
      for (final y in system.stringLines) {
        canvas.drawLine(
          Offset(system.rect.left * size.width, y * size.height),
          Offset(system.rect.right * size.width, y * size.height),
          linePaint,
        );
      }
      for (final risk in system.connectedNotationRisks) {
        final color = switch (risk.side) {
          VisualConnectedComponentSide.unresolved => Colors.redAccent,
          VisualConnectedComponentSide.upper => Colors.deepPurpleAccent,
          VisualConnectedComponentSide.lower => Colors.amberAccent,
        };
        final rect = Rect.fromLTRB(
          risk.rect.left * size.width,
          risk.rect.top * size.height,
          risk.rect.right * size.width,
          risk.rect.bottom * size.height,
        );
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      for (final token in system.tokens) {
        final selected = selectedTokenIds.contains(token.id);
        final color = selected
            ? Colors.yellowAccent
            : switch (token.kind) {
                VisualTabTokenKind.fret => Colors.lightGreenAccent,
                VisualTabTokenKind.deadNote => Colors.cyanAccent,
                VisualTabTokenKind.measureNumber => Colors.orangeAccent,
                VisualTabTokenKind.ambiguous => Colors.redAccent,
              };
        final rect = Rect.fromLTRB(
          token.rect.left * size.width,
          token.rect.top * size.height,
          token.rect.right * size.width,
          token.rect.bottom * size.height,
        );
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: token.enabled ? 0.22 : 0.08),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.5 : 1.3,
        );
      }
    }
    if (drawStart != null && drawEnd != null) {
      final rect = Rect.fromPoints(
        Offset(drawStart!.dx * size.width, drawStart!.dy * size.height),
        Offset(drawEnd!.dx * size.width, drawEnd!.dy * size.height),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.yellowAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnalysisOverlayPainter oldDelegate) => true;
}

Uint8List _renderAnalysisPreview(Map<String, Object?> request) {
  final strip = VisualStrip.fromJson(
    (request['strip']! as Map).cast<String, Object?>(),
  );
  return const VisualImageProcessor().process(
    request['bytes']! as Uint8List,
    strip,
    maxWidth: 1800,
  );
}
