import 'package:flutter/material.dart';

import '../../application/visual_tuning_parser.dart';
import '../../domain/visual_tab_transform_models.dart';

Future<VisualTabTransformConfiguration?> showVisualTabTransformDialog({
  required BuildContext context,
  required int sourceStringCount,
  VisualTabTransformConfiguration? initialValue,
  bool showCompactOption = true,
}) {
  return showDialog<VisualTabTransformConfiguration>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _VisualTabTransformDialog(
      sourceStringCount: sourceStringCount,
      initialValue: initialValue,
      showCompactOption: showCompactOption,
    ),
  );
}

enum _TransformPreset {
  custom,
  allStrings,
  standardGuitar,
  dropCSharpToDropA7,
  dropDToBeadg,
  halfStepDownToBeadg,
}

enum _TuningEdge { high, low }

class _TuningEdit {
  const _TuningEdit(this.value, {this.edge, this.delta = 0});

  final String value;
  final _TuningEdge? edge;
  final int delta;

  bool get changedStringCount => delta != 0;
}

class _VisualTabTransformDialog extends StatefulWidget {
  const _VisualTabTransformDialog({
    required this.sourceStringCount,
    required this.initialValue,
    required this.showCompactOption,
  });

  final int sourceStringCount;
  final VisualTabTransformConfiguration? initialValue;
  final bool showCompactOption;

  @override
  State<_VisualTabTransformDialog> createState() =>
      _VisualTabTransformDialogState();
}

class _VisualTabTransformDialogState extends State<_VisualTabTransformDialog> {
  late final TextEditingController _source;
  late final TextEditingController _target;
  late final TextEditingController _sourceCapo;
  late final TextEditingController _targetCapo;
  late final TextEditingController _pitchChange;
  late final TextEditingController _selectedChanges;
  late List<int> _routeTargets;
  final Map<int, int?> _manualOffsets = {};
  _TransformPreset _preset = _TransformPreset.custom;
  bool _advanced = false;
  bool _advancedTunings = false;
  bool _compactTabOnly = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _source = TextEditingController(
      text: initial == null
          ? _defaultSource(widget.sourceStringCount)
          : _formatTuning(initial.sourceLabels, initial.sourceOpenMidis),
    );
    _target = TextEditingController(
      text: initial == null
          ? _defaultSource(widget.sourceStringCount)
          : _formatTuning(initial.targetLabels, initial.targetOpenMidis),
    );
    _sourceCapo = TextEditingController(text: '${initial?.sourceCapo ?? 0}');
    _targetCapo = TextEditingController(text: '${initial?.targetCapo ?? 0}');
    _pitchChange = TextEditingController(
      text: '${initial?.globalPitchChange ?? 0}',
    );
    _selectedChanges = TextEditingController(
      text: initial == null
          ? ''
          : initial.selectedStringPitchChanges.entries
                .map(
                  (entry) =>
                      '${initial.sourceLabels.length - entry.key}:'
                      '${_signed(entry.value)}',
                )
                .join(', '),
    );
    _routeTargets =
        initial?.routes.map((route) => route.targetString).toList() ??
        List.generate(widget.sourceStringCount, (index) => index);
    if (initial != null) {
      for (final route in initial.routes) {
        _manualOffsets[route.sourceString] = route.manualOffset;
      }
      _compactTabOnly = true;
    }
  }

  @override
  void dispose() {
    _source.dispose();
    _target.dispose();
    _sourceCapo.dispose();
    _targetCapo.dispose();
    _pitchChange.dispose();
    _selectedChanges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _tryPreview();
    return AlertDialog(
      title: const Text('Visual tab transform'),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<_TransformPreset>(
                initialValue: _preset,
                decoration: const InputDecoration(labelText: 'Starting preset'),
                items: const [
                  DropdownMenuItem(
                    value: _TransformPreset.custom,
                    child: Text('Custom / current values'),
                  ),
                  DropdownMenuItem(
                    value: _TransformPreset.allStrings,
                    child: Text('All strings: pitch change only'),
                  ),
                  DropdownMenuItem(
                    value: _TransformPreset.standardGuitar,
                    child: Text('Standard guitar EADGBE 6-string → 6-string'),
                  ),
                  DropdownMenuItem(
                    value: _TransformPreset.dropCSharpToDropA7,
                    child: Text('Drop-C# 6-string → Drop-A 7-string'),
                  ),
                  DropdownMenuItem(
                    value: _TransformPreset.dropDToBeadg,
                    child: Text('Drop-D 4-string → BEADG 5-string'),
                  ),
                  DropdownMenuItem(
                    value: _TransformPreset.halfStepDownToBeadg,
                    child: Text('Half-step-down 4-string → BEADG 5-string'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) _applyPreset(value);
                },
              ),
              const SizedBox(height: 10),
              _TuningOffsetRows(
                id: 'source-tuning',
                label: 'Source open-string tuning · high → low',
                tuningSpec: _source.text,
                onChanged: (edit) {
                  _source.text = edit.value;
                  _preset = _TransformPreset.custom;
                  _refreshRoutes(reset: edit.changedStringCount);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TuningOffsetRows(
                      id: 'target-tuning',
                      label: 'Target open-string tuning · high → low',
                      tuningSpec: _target.text,
                      onChanged: (edit) {
                        _target.text = edit.value;
                        _preset = _TransformPreset.custom;
                        _refreshRoutes(reset: edit.changedStringCount);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _sourceCapo,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Source capo',
                        helperText: 'Before routing',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _targetCapo,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Target capo',
                        helperText: 'After routing',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _pitchChange,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Global pitch change',
                        helperText: 'Semitones, e.g. +1 or -2',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _selectedChanges,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Selected-string overrides (optional)',
                        helperText:
                            'Tab string number (top to bottom):change, e.g. 1:+3',
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _advancedTunings,
                onChanged: (value) => setState(() => _advancedTunings = value),
                title: const Text('Advanced arbitrary tuning / octave entry'),
                subtitle: const Text(
                  'Edit confirmed internal low-to-high label:MIDI values '
                  'directly.',
                ),
              ),
              if (_advancedTunings) ...[
                TextField(
                  controller: _source,
                  onChanged: (_) => _refreshRoutes(),
                  decoration: const InputDecoration(
                    labelText: 'Advanced source tuning, low → high',
                    helperText: 'Format: label:MIDI, label:MIDI',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _target,
                  onChanged: (_) => _refreshRoutes(),
                  decoration: const InputDecoration(
                    labelText: 'Advanced target tuning, low → high',
                    helperText:
                        'Target may have the same or more strings, up to 12.',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (preview case final routePreview?) ...[
                Text(
                  'Target strings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  routePreview.unusedTargetStrings.isEmpty
                      ? 'Every target string is used for this transform.'
                      : '${routePreview.unusedTargetStrings.length} added '
                            'target string(s) stay blank until music is routed '
                            'to them.',
                ),
                const SizedBox(height: 4),
                for (
                  var targetIndex = routePreview.targetLabels.length - 1;
                  targetIndex >= 0;
                  targetIndex -= 1
                )
                  SwitchListTile(
                    key: ValueKey('target-string-enabled-$targetIndex'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: routePreview.routes.any(
                      (route) => route.targetString == targetIndex,
                    ),
                    onChanged:
                        routePreview.targetLabels.length ==
                            routePreview.sourceLabels.length + 1
                        ? (enabled) => _setTargetStringEnabled(
                            routePreview,
                            targetIndex,
                            enabled,
                          )
                        : null,
                    title: Text(
                      '${routePreview.targetLabels.length - targetIndex}. '
                      '${routePreview.targetLabels[targetIndex]}',
                    ),
                    subtitle: Text(
                      routePreview.routes.any(
                            (route) => route.targetString == targetIndex,
                          )
                          ? 'Used by source string '
                                '${routePreview.sourceLabels.length - routePreview.routes.indexWhere((route) => route.targetString == targetIndex)}'
                          : 'Added target string - unused',
                    ),
                  ),
                const Divider(height: 20),
                Text(
                  'Source-string routing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (
                  var sourceIndex = routePreview.sourceLabels.length - 1;
                  sourceIndex >= 0;
                  sourceIndex -= 1
                )
                  _routeRow(routePreview, sourceIndex),
                if (routePreview.unusedTargetStrings.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Unused target strings: '
                      '${routePreview.unusedTargetStrings.map((unused) => '${routePreview.targetLabels.length - unused} (${routePreview.targetLabels[unused]})').join(', ')}.',
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _advanced,
                onChanged: (value) => setState(() => _advanced = value),
                title: const Text('Advanced manual fret offsets'),
                subtitle: const Text(
                  'Manual overrides can change sounding pitch and are warned.',
                ),
              ),
              if (widget.showCompactOption)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _compactTabOnly,
                  onChanged: null,
                  title: const Text(
                    'Compact transformed tab systems (current output)',
                  ),
                  subtitle: const Text(
                    'Original assets remain recoverable. Full-page notation '
                    'output is not offered because standard notation would '
                    'not be transposed safely.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.transform),
          label: const Text('Apply transform'),
        ),
      ],
    );
  }

  Widget _routeRow(_TransformRoutePreview preview, int sourceIndex) {
    final route = preview.routes[sourceIndex];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              '${preview.sourceLabels.length - sourceIndex}. '
              '${preview.sourceLabels[sourceIndex]}',
            ),
          ),
          const Icon(Icons.arrow_forward, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<int>(
              initialValue: _routeTargets[sourceIndex],
              decoration: const InputDecoration(
                labelText: 'Target string',
                isDense: true,
              ),
              items: [
                for (
                  var index = preview.targetLabels.length - 1;
                  index >= 0;
                  index -= 1
                )
                  DropdownMenuItem(
                    value: index,
                    child: Text(
                      '${preview.targetLabels.length - index}. '
                      '${preview.targetLabels[index]}',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _routeTargets[sourceIndex] = value;
                  _preset = _TransformPreset.custom;
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Calculated ${_signed(route.fretOffset)} fret'
              '${route.fretOffset.abs() == 1 ? "" : "s"}',
            ),
          ),
          if (_advanced)
            SizedBox(
              width: 130,
              child: TextFormField(
                initialValue: route.manualOffset?.toString() ?? '',
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                onChanged: (value) {
                  _manualOffsets[sourceIndex] = value.trim().isEmpty
                      ? null
                      : int.tryParse(value);
                },
                decoration: const InputDecoration(
                  labelText: 'Override',
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _applyPreset(_TransformPreset preset) {
    setState(() {
      _preset = preset;
      _manualOffsets.clear();
      switch (preset) {
        case _TransformPreset.custom:
          return;
        case _TransformPreset.allStrings:
          _source.text = _defaultSource(widget.sourceStringCount);
          _target.text = _source.text;
          _sourceCapo.text = '0';
          _targetCapo.text = '0';
          _pitchChange.text = '+1';
          _selectedChanges.clear();
          _routeTargets = List.generate(
            widget.sourceStringCount,
            (index) => index,
          );
        case _TransformPreset.standardGuitar:
          _source.text = 'E:40, A:45, D:50, G:55, B:59, E:64';
          _target.text = _source.text;
          _sourceCapo.text = '0';
          _targetCapo.text = '0';
          _pitchChange.text = '0';
          _selectedChanges.clear();
          _routeTargets = List.generate(6, (index) => index);
        case _TransformPreset.dropCSharpToDropA7:
          _source.text = 'C#:37, G#:44, C#:49, F#:54, A#:58, D#:63';
          _target.text = 'A:33, E:40, A:45, D:50, G:55, B:59, E:64';
          _sourceCapo.text = '0';
          _targetCapo.text = '0';
          _pitchChange.text = '0';
          _selectedChanges.clear();
          _routeTargets = [0, 1, 2, 3, 4, 5];
        case _TransformPreset.dropDToBeadg:
          _source.text = 'D:26, A:33, D:38, G:43';
          _target.text = 'B:23, E:28, A:33, D:38, G:43';
          _sourceCapo.text = '0';
          _targetCapo.text = '0';
          _pitchChange.text = '0';
          _selectedChanges.clear();
          _routeTargets = [0, 2, 3, 4];
        case _TransformPreset.halfStepDownToBeadg:
          _source.text = 'D#:27, G#:32, C#:37, F#:42';
          _target.text = 'B:23, E:28, A:33, D:38, G:43';
          _sourceCapo.text = '0';
          _targetCapo.text = '2';
          _pitchChange.text = '-2';
          _selectedChanges.clear();
          _routeTargets = [0, 1, 2, 3];
      }
      _error = null;
    });
  }

  void _setTargetStringEnabled(
    _TransformRoutePreview preview,
    int targetIndex,
    bool enabled,
  ) {
    if (preview.targetLabels.length != preview.sourceLabels.length + 1) return;
    final used = _routeTargets.toSet();
    final isUsed = used.contains(targetIndex);
    if (enabled == isUsed) return;
    setState(() {
      if (!enabled) {
        _routeTargets = [
          for (var index = 0; index < preview.targetLabels.length; index += 1)
            if (index != targetIndex) index,
        ];
      } else {
        final priorUnused = preview.unusedTargetString;
        var replacementUnused = preview.targetLabels.length - 1;
        if (replacementUnused == targetIndex) replacementUnused = 0;
        if (priorUnused != null && priorUnused != targetIndex) {
          replacementUnused = priorUnused;
        }
        _routeTargets = [
          for (var index = 0; index < preview.targetLabels.length; index += 1)
            if (index != replacementUnused) index,
        ];
      }
      _preset = _TransformPreset.custom;
      _manualOffsets.clear();
      _error = null;
    });
  }

  void _refreshRoutes({bool reset = false}) {
    setState(() {
      try {
        final source = parseVisualTuningSpec(_source.text);
        final target = parseVisualTuningSpec(_target.text);
        if (reset || _routeTargets.length != source.labels.length) {
          _routeTargets = _defaultRouteTargets(
            source.openMidis,
            target.openMidis,
          );
        } else {
          _routeTargets = [
            for (final value in _routeTargets)
              value.clamp(0, target.labels.length - 1),
          ];
        }
      } catch (_) {
        // Keep the user's partially entered value until Apply.
      }
    });
  }

  _TransformRoutePreview? _tryPreview() {
    try {
      final source = parseVisualTuningSpec(_source.text);
      final target = parseVisualTuningSpec(_target.text);
      if (_routeTargets.length != source.labels.length) return null;
      final sourceCapo = int.tryParse(_sourceCapo.text.trim());
      final targetCapo = int.tryParse(_targetCapo.text.trim());
      final globalPitch = int.tryParse(_pitchChange.text.trim());
      if (sourceCapo == null || targetCapo == null || globalPitch == null) {
        return null;
      }
      final displayedSelected = parseSelectedStringPitchChanges(
        _selectedChanges.text,
        sourceStringCount: source.labels.length,
      );
      final selected = {
        for (final entry in displayedSelected.entries)
          source.labels.length - 1 - entry.key: entry.value,
      };
      final routes = <VisualStringRoute>[];
      for (
        var sourceIndex = 0;
        sourceIndex < source.labels.length;
        sourceIndex += 1
      ) {
        final targetIndex = _routeTargets[sourceIndex];
        if (targetIndex < 0 || targetIndex >= target.labels.length) return null;
        routes.add(
          VisualStringRoute(
            sourceString: sourceIndex,
            targetString: targetIndex,
            fretOffset: calculateVisualRouteFretOffset(
              sourceOpenMidi: source.openMidis[sourceIndex],
              sourceCapo: sourceCapo,
              desiredPitchChange: selected[sourceIndex] ?? globalPitch,
              targetOpenMidi: target.openMidis[targetIndex],
              targetCapo: targetCapo,
            ),
            manualOffset: _manualOffsets[sourceIndex],
          ),
        );
      }
      return _TransformRoutePreview(
        sourceLabels: source.labels,
        targetLabels: target.labels,
        routes: routes,
      );
    } catch (_) {
      return null;
    }
  }

  VisualTabTransformConfiguration _configuration() {
    final source = parseVisualTuningSpec(_source.text);
    final target = parseVisualTuningSpec(_target.text);
    if (_routeTargets.length != source.labels.length) {
      throw const FormatException('Every source string needs a target route.');
    }
    final sourceCapo = int.tryParse(_sourceCapo.text.trim());
    final targetCapo = int.tryParse(_targetCapo.text.trim());
    final globalPitch = int.tryParse(_pitchChange.text.trim());
    if (sourceCapo == null || targetCapo == null || globalPitch == null) {
      throw const FormatException('Capos and pitch change must be numbers.');
    }
    if (globalPitch < -24 || globalPitch > 24) {
      throw const FormatException('Pitch change must be -24 to +24.');
    }
    final displayedSelected = parseSelectedStringPitchChanges(
      _selectedChanges.text,
      sourceStringCount: source.labels.length,
    );
    final selected = {
      for (final entry in displayedSelected.entries)
        source.labels.length - 1 - entry.key: entry.value,
    };
    final routes = <VisualStringRoute>[];
    for (
      var sourceIndex = 0;
      sourceIndex < source.labels.length;
      sourceIndex += 1
    ) {
      final targetIndex = _routeTargets[sourceIndex];
      final offset = calculateVisualRouteFretOffset(
        sourceOpenMidi: source.openMidis[sourceIndex],
        sourceCapo: sourceCapo,
        desiredPitchChange: selected[sourceIndex] ?? globalPitch,
        targetOpenMidi: target.openMidis[targetIndex],
        targetCapo: targetCapo,
      );
      routes.add(
        VisualStringRoute(
          sourceString: sourceIndex,
          targetString: targetIndex,
          fretOffset: offset,
          manualOffset: _manualOffsets[sourceIndex],
        ),
      );
    }
    return VisualTabTransformConfiguration(
      sourceLabels: source.labels,
      sourceOpenMidis: source.openMidis,
      sourceCapo: sourceCapo,
      targetLabels: target.labels,
      targetOpenMidis: target.openMidis,
      targetCapo: targetCapo,
      globalPitchChange: globalPitch,
      selectedStringPitchChanges: selected,
      routes: routes,
      compactTabOnly: _compactTabOnly,
    );
  }

  void _submit() {
    try {
      final configuration = _configuration();
      setState(() => _error = null);
      Navigator.pop(context, configuration);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class _TuningOffsetRows extends StatefulWidget {
  const _TuningOffsetRows({
    required this.id,
    required this.label,
    required this.tuningSpec,
    required this.onChanged,
  });

  final String id;
  final String label;
  final String tuningSpec;
  final ValueChanged<_TuningEdit> onChanged;

  @override
  State<_TuningOffsetRows> createState() => _TuningOffsetRowsState();
}

class _TuningOffsetRowsState extends State<_TuningOffsetRows> {
  late List<String> _baseLabels;
  late List<int> _baseMidis;
  final List<TextEditingController> _offsets = [];
  String? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _load(widget.tuningSpec);
  }

  @override
  void didUpdateWidget(covariant _TuningOffsetRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tuningSpec != oldWidget.tuningSpec &&
        widget.tuningSpec != _lastEmitted) {
      _load(widget.tuningSpec);
    }
  }

  @override
  void dispose() {
    for (final controller in _offsets) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(String value) {
    late final ParsedVisualTuning tuning;
    try {
      tuning = parseVisualTuningSpec(value);
    } on FormatException {
      return;
    }
    _baseLabels = [...tuning.labels];
    _baseMidis = [...tuning.openMidis];
    for (final controller in _offsets) {
      controller.dispose();
    }
    _offsets
      ..clear()
      ..addAll([
        for (var index = 0; index < _baseMidis.length; index += 1)
          TextEditingController(text: '0'),
      ]);
    _lastEmitted = null;
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        helperText:
            'Open-string changes are separate from song pitch, capo, and '
            'selected-string overrides.',
        border: const OutlineInputBorder(),
      ),
      child: Column(
        children: [
          _StringEdgeControls(
            addKey: ValueKey('${widget.id}-add-high-string'),
            removeKey: ValueKey('${widget.id}-remove-high-string'),
            addLabel:
                'Add string above ${_calculatedName(_baseMidis.length - 1)}',
            removeTooltip: 'Remove highest string',
            canAdd: _baseMidis.length < 12,
            canRemove: _baseMidis.length > 2,
            onAdd: () => _changeStringCount(_TuningEdge.high, 1),
            onRemove: () => _changeStringCount(_TuningEdge.high, -1),
          ),
          const SizedBox(height: 4),
          for (
            var displayIndex = 0;
            displayIndex < _baseMidis.length;
            displayIndex += 1
          )
            Padding(
              padding: EdgeInsets.only(
                bottom: displayIndex == _baseMidis.length - 1 ? 0 : 6,
              ),
              child: Builder(
                builder: (context) {
                  final index = _baseMidis.length - 1 - displayIndex;
                  return Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          '${displayIndex + 1}. ${_baseLabels[index]}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip:
                            'Lower string ${displayIndex + 1} by one semitone',
                        onPressed: () => _step(index, -1),
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _offsets[index],
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                          ),
                          onChanged: (_) {
                            setState(() {});
                            _emit();
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'semitones',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip:
                            'Raise string ${displayIndex + 1} by one semitone',
                        onPressed: () => _step(index, 1),
                        icon: const Icon(Icons.add),
                      ),
                      const Icon(Icons.arrow_forward, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _calculatedLabel(index),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
          _StringEdgeControls(
            addKey: ValueKey('${widget.id}-add-low-string'),
            removeKey: ValueKey('${widget.id}-remove-low-string'),
            addLabel: 'Add string below ${_calculatedName(0)}',
            removeTooltip: 'Remove lowest string',
            canAdd: _baseMidis.length < 12,
            canRemove: _baseMidis.length > 2,
            onAdd: () => _changeStringCount(_TuningEdge.low, 1),
            onRemove: () => _changeStringCount(_TuningEdge.low, -1),
          ),
        ],
      ),
    );
  }

  void _step(int index, int amount) {
    final current = int.tryParse(_offsets[index].text.trim()) ?? 0;
    _offsets[index].text = (current + amount).clamp(-24, 24).toInt().toString();
    setState(() {});
    _emit();
  }

  int _offset(int index) =>
      (int.tryParse(_offsets[index].text.trim()) ?? 0).clamp(-24, 24).toInt();

  String _calculatedLabel(int index) {
    final midi = (_baseMidis[index] + _offset(index)).clamp(0, 127).toInt();
    return '${_noteName(midi)}  (MIDI $midi)';
  }

  void _emit() {
    final value = [
      for (var index = 0; index < _baseMidis.length; index += 1)
        '${_noteName((_baseMidis[index] + _offset(index)).clamp(0, 127).toInt())}:'
            '${(_baseMidis[index] + _offset(index)).clamp(0, 127).toInt()}',
    ].join(', ');
    _lastEmitted = value;
    widget.onChanged(_TuningEdit(value));
  }

  String _calculatedName(int index) =>
      _noteName((_baseMidis[index] + _offset(index)).clamp(0, 127).toInt());

  void _changeStringCount(_TuningEdge edge, int delta) {
    if (delta > 0 && _baseMidis.length >= maximumVisualTabStringCount) return;
    if (delta < 0 && _baseMidis.length <= minimumVisualTabStringCount) return;
    final midis = [
      for (var index = 0; index < _baseMidis.length; index += 1)
        (_baseMidis[index] + _offset(index)).clamp(0, 127).toInt(),
    ];
    if (delta > 0) {
      if (edge == _TuningEdge.high) {
        final interval = midis.last % 12 == 7 ? 4 : 5;
        midis.add((midis.last + interval).clamp(0, 127));
      } else {
        midis.insert(0, (midis.first - 5).clamp(0, 127));
      }
    } else if (edge == _TuningEdge.high) {
      midis.removeLast();
    } else {
      midis.removeAt(0);
    }
    _replaceMidis(midis);
    widget.onChanged(_TuningEdit(_lastEmitted!, edge: edge, delta: delta));
  }

  void _replaceMidis(List<int> midis) {
    for (final controller in _offsets) {
      controller.dispose();
    }
    setState(() {
      _baseMidis = [...midis];
      _baseLabels = [for (final midi in midis) _noteName(midi)];
      _offsets
        ..clear()
        ..addAll([
          for (var index = 0; index < midis.length; index += 1)
            TextEditingController(text: '0'),
        ]);
      _lastEmitted = [
        for (var index = 0; index < midis.length; index += 1)
          '${_baseLabels[index]}:${midis[index]}',
      ].join(', ');
    });
  }

  String _noteName(int midi) => const [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ][midi % 12];
}

class _StringEdgeControls extends StatelessWidget {
  const _StringEdgeControls({
    required this.addKey,
    required this.removeKey,
    required this.addLabel,
    required this.removeTooltip,
    required this.canAdd,
    required this.canRemove,
    required this.onAdd,
    required this.onRemove,
  });

  final Key addKey;
  final Key removeKey;
  final String addLabel;
  final String removeTooltip;
  final bool canAdd;
  final bool canRemove;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      TextButton.icon(
        key: addKey,
        onPressed: canAdd ? onAdd : null,
        icon: const Icon(Icons.add),
        label: Text(addLabel),
      ),
      const Spacer(),
      IconButton(
        key: removeKey,
        tooltip: removeTooltip,
        onPressed: canRemove ? onRemove : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
    ],
  );
}

List<int> _defaultRouteTargets(List<int> source, List<int> target) {
  if (source.isEmpty || target.isEmpty) return const [];
  final exact = <int>[];
  var prior = -1;
  for (final midi in source) {
    var match = -1;
    for (var index = prior + 1; index < target.length; index += 1) {
      if (target[index] == midi) {
        match = index;
        break;
      }
    }
    if (match < 0) {
      exact.clear();
      break;
    }
    exact.add(match);
    prior = match;
  }
  if (exact.length == source.length) return exact;
  final offset = target.length >= source.length && target.first < source.first
      ? target.length - source.length
      : 0;
  return [
    for (var index = 0; index < source.length; index += 1)
      (index + offset).clamp(0, target.length - 1),
  ];
}

String _defaultSource(int count) => switch (count) {
  4 => 'E:28, A:33, D:38, G:43',
  5 => 'B:23, E:28, A:33, D:38, G:43',
  _ => List.generate(
    count,
    (index) => 'S${index + 1}:${20 + index * 5}',
  ).join(', '),
};

String _formatTuning(List<String> labels, List<int> midis) => [
  for (var index = 0; index < labels.length; index += 1)
    '${labels[index]}:${midis[index]}',
].join(', ');

String _signed(int value) => value >= 0 ? '+$value' : '$value';

class _TransformRoutePreview {
  const _TransformRoutePreview({
    required this.sourceLabels,
    required this.targetLabels,
    required this.routes,
  });

  final List<String> sourceLabels;
  final List<String> targetLabels;
  final List<VisualStringRoute> routes;

  List<int> get unusedTargetStrings {
    final used = routes.map((route) => route.targetString).toSet();
    return [
      for (var index = 0; index < targetLabels.length; index += 1)
        if (!used.contains(index)) index,
    ];
  }

  int? get unusedTargetString {
    final unused = unusedTargetStrings;
    return unused.length == 1 ? unused.single : null;
  }
}
