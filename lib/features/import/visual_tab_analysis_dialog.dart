import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/service_contracts.dart';
import '../../application/visual_analysis_review_session.dart';
import '../../application/visual_tab_analysis_service.dart';
import '../../domain/visual_chart_models.dart';
import '../../domain/visual_tab_transform_models.dart';
import 'visual_analysis_inspector.dart';
import 'visual_analysis_row_list.dart';
import 'visual_analysis_toolbar.dart';

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
  late final VisualAnalysisReviewSession _review;
  final Set<String> _selectedTokenIds = {};
  bool _rerunningSource = false;
  bool _drawing = false;
  Offset? _drawStart;
  Offset? _drawEnd;

  List<VisualTabAnalysis?> get _analyses => _review.analyses;
  List<VisualAnalysisRowState> get _rowStates => _review.rowStates;
  Map<int, Object> get _rowErrors => _review.rowErrors;
  int get _currentIndex => _review.currentIndex;
  set _currentIndex(int value) => _review.select(value);
  int get _processed => _review.processed;
  VisualTabAnalysis get _analysis => _review.analysis;
  VisualTabAnalysis? get _currentAnalysis => _review.currentAnalysis;

  @override
  void initState() {
    super.initState();
    _review = VisualAnalysisReviewSession(
      analyzer: widget.analyzer,
      strips: widget.strips,
      sourceStringCount: widget.sourceStringCount,
    );
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
    for (var index = 0; index < widget.strips.length; index += 1) {
      await _analyzeIndex(index, preferPositionedPdf: false);
      if (!mounted) return;
    }
  }

  Future<void> _analyzeIndex(
    int index, {
    bool preferPositionedPdf = true,
  }) async {
    if (!mounted) return;
    await _review.analyzeIndex(
      index,
      preferPositionedPdf: preferPositionedPdf,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final processingComplete = _review.processingComplete;
    final blockedRows = _review.blockedRows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review visual tab analysis'),
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          if (_currentAnalysis != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('${_currentIndex + 1} / ${widget.strips.length}'),
              ),
            ),
          FilledButton.icon(
            onPressed: processingComplete
                ? () => _finishReview(blockedRows)
                : null,
            icon: Icon(
              blockedRows.isEmpty ? Icons.check : Icons.warning_amber_rounded,
            ),
            label: Text(
              blockedRows.isEmpty
                  ? 'Use reviewed analysis'
                  : 'Continue (${blockedRows.length} unchanged)',
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _buildBody(processingComplete),
    );
  }

  Widget _buildBody(bool processingComplete) {
    return Column(
      children: [
        if (!processingComplete)
          LinearProgressIndicator(
            value: widget.strips.isEmpty
                ? null
                : _processed / widget.strips.length,
          ),
        if (_currentAnalysis != null)
          VisualAnalysisToolbar(
            analyses: _analyses,
            currentIndex: _currentIndex,
            analysis: _analysis,
            rerunningSource: _rerunningSource,
            drawing: _drawing,
            stripCount: widget.strips.length,
            selectedTokenCount: _selectedTokenIds.length,
            onRowSelected: (value) {
              setState(() {
                _currentIndex = value;
                _selectedTokenIds.clear();
              });
            },
            onRerunCurrent: _rerunCurrentWithOcr,
            onRerunAll: _rerunAllWithOcr,
            onDrawingChanged: (value) => setState(() => _drawing = value),
            onEdit: _editSelected,
            onMerge: _mergeSelected,
            onSplit: _splitSelected,
            onDelete: _deleteSelected,
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: VisualAnalysisRowList(
                  library: widget.library,
                  strips: widget.strips,
                  analyses: _analyses,
                  rowStates: _rowStates,
                  rowErrors: _rowErrors,
                  currentIndex: _currentIndex,
                  selectedTokenIds: _selectedTokenIds,
                  drawing: _drawing,
                  drawStart: _drawStart,
                  drawEnd: _drawEnd,
                  onRetry: _analyzeIndex,
                  onActivateRow: _activateRow,
                  onTokenTap: _activateAndToggle,
                  onDrawStart: (index, position) {
                    _activateRow(index);
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
              VisualAnalysisInspector(
                analysis: _currentAnalysis,
                selectedTokenIds: _selectedTokenIds,
                onToggleToken: _toggleToken,
                onSetRiskSide: _setRiskSide,
                onRemoveRisk: _removeRisk,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _finishReview(List<int> blockedRows) async {
    if (blockedRows.isEmpty) {
      Navigator.pop(
        context,
        List<VisualTabAnalysis>.unmodifiable(
          _analyses.whereType<VisualTabAnalysis>(),
        ),
      );
      return;
    }
    final rowLabels = blockedRows.map((index) => index + 1).join(', ');
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          blockedRows.length == 1
              ? 'Row $rowLabels has no usable fret tokens'
              : '${blockedRows.length} rows have no usable fret tokens',
        ),
        content: Text(
          'Raster/OCR could not produce an enabled fret or dead-note token '
          'for row(s) $rowLabels. You can return to review them, or continue '
          'and keep those source rows visually unchanged. They will not be '
          'silently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review blocked row'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keep unchanged and continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (keep != true) {
      setState(() {
        _currentIndex = blockedRows.first;
        _selectedTokenIds.clear();
      });
      return;
    }
    final reviewed = <VisualTabAnalysis>[
      for (var index = 0; index < _analyses.length; index += 1)
        _analyses[index]!.copyWith(keepUnchanged: blockedRows.contains(index)),
    ];
    Navigator.pop(context, List<VisualTabAnalysis>.unmodifiable(reviewed));
  }

  void _activateRow(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      _selectedTokenIds.clear();
      _drawStart = null;
      _drawEnd = null;
    });
  }

  void _activateAndToggle(int index, String id) {
    setState(() {
      if (_currentIndex != index) {
        _currentIndex = index;
        _selectedTokenIds.clear();
      }
      if (!_selectedTokenIds.add(id)) _selectedTokenIds.remove(id);
    });
  }

  Future<void> _rerunCurrentWithOcr() async {
    setState(() {
      _rerunningSource = true;
      _selectedTokenIds.clear();
    });
    try {
      await _analyzeIndex(_currentIndex, preferPositionedPdf: false);
    } finally {
      if (mounted) setState(() => _rerunningSource = false);
    }
  }

  Future<void> _rerunAllWithOcr() async {
    setState(() {
      _rerunningSource = true;
      _selectedTokenIds.clear();
    });
    try {
      for (var index = 0; index < widget.strips.length; index += 1) {
        if (!mounted) return;
        setState(() => _currentIndex = index);
        await _analyzeIndex(index, preferPositionedPdf: false);
      }
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
      _review.replaceCurrent(_analysis.copyWith(systems: systems));
    });
  }

  void _removeRisk(String systemId, String riskId) {
    setState(() {
      final systems = [
        for (final system in _analysis.systems)
          if (system.id != systemId)
            system
          else
            system.copyWith(
              connectedNotationRisks: [
                for (final risk in system.connectedNotationRisks)
                  if (risk.id != riskId) risk,
              ],
            ),
      ];
      _review.replaceCurrent(_analysis.copyWith(systems: systems));
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
      _review.replaceCurrent(_analysis.copyWith(systems: systems));
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
      _review.replaceCurrent(_analysis.copyWith(systems: systems));
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
      _review.replaceCurrent(_analysis.copyWith(systems: systems));
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
