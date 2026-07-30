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

enum _TransformPreset { custom, allStrings, dropDToBeadg, halfStepDownToBeadg }

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
                .map((entry) => '${entry.key + 1}:${_signed(entry.value)}')
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
                label: 'Source open-string tuning · low → high',
                tuningSpec: _source.text,
                onChanged: (value) {
                  _source.text = value;
                  _refreshRoutes();
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TuningOffsetRows(
                      label: 'Target open-string tuning · low → high',
                      tuningSpec: _target.text,
                      onChanged: (value) {
                        _target.text = value;
                        _refreshRoutes();
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
                            'Low-to-high string number:change, e.g. 1:+3',
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
                  'Edit confirmed low-to-high label:MIDI values directly.',
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
                        'Target may have the same strings or one extra.',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (preview case final routePreview?) ...[
                Text(
                  'Source-string routing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (
                  var sourceIndex = 0;
                  sourceIndex < routePreview.sourceLabels.length;
                  sourceIndex += 1
                )
                  _routeRow(routePreview, sourceIndex),
                if (routePreview.unusedTargetString case final unused?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Unused target string: ${unused + 1} '
                      '(${routePreview.targetLabels[unused]}).',
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
              '${sourceIndex + 1}. ${preview.sourceLabels[sourceIndex]}',
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
                  var index = 0;
                  index < preview.targetLabels.length;
                  index += 1
                )
                  DropdownMenuItem(
                    value: index,
                    child: Text('${index + 1}. ${preview.targetLabels[index]}'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _routeTargets[sourceIndex] = value);
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

  void _refreshRoutes() {
    setState(() {
      try {
        final source = parseVisualTuningSpec(_source.text);
        final target = parseVisualTuningSpec(_target.text);
        if (_routeTargets.length != source.labels.length) {
          _routeTargets = List.generate(
            source.labels.length,
            (index) => index.clamp(0, target.labels.length - 1),
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
      final selected = parseSelectedStringPitchChanges(
        _selectedChanges.text,
        sourceStringCount: source.labels.length,
      );
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
    if (source.labels.length != widget.sourceStringCount) {
      throw FormatException(
        'Reviewed analysis has ${widget.sourceStringCount} strings, but the '
        'source tuning has ${source.labels.length}.',
      );
    }
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
    final selected = parseSelectedStringPitchChanges(
      _selectedChanges.text,
      sourceStringCount: source.labels.length,
    );
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
    required this.label,
    required this.tuningSpec,
    required this.onChanged,
  });

  final String label;
  final String tuningSpec;
  final ValueChanged<String> onChanged;

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
          for (var index = 0; index < _baseMidis.length; index += 1)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == _baseMidis.length - 1 ? 0 : 6,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      '${index + 1}. ${_baseLabels[index]}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lower string ${index + 1} by one semitone',
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
                    tooltip: 'Raise string ${index + 1} by one semitone',
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
              ),
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
    widget.onChanged(value);
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

  int? get unusedTargetString {
    if (targetLabels.length != sourceLabels.length + 1) return null;
    final used = routes.map((route) => route.targetString).toSet();
    for (var index = 0; index < targetLabels.length; index += 1) {
      if (!used.contains(index)) return index;
    }
    return null;
  }
}
