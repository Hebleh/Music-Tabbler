import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/semantic_edit_session.dart';
import '../../domain/music_models.dart';
import '../../domain/device_preferences.dart';
import '../../application/service_contracts.dart';
import 'tab_chart_view.dart';

class ChartEditorScreen extends StatefulWidget {
  const ChartEditorScreen({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
    required this.repository,
    required this.pdfExporter,
    required this.chart,
    required this.songId,
  });

  final DevicePreferences preferences;
  final ValueChanged<DevicePreferences> onPreferencesChanged;
  final SemanticChartLibrary repository;
  final SemanticChartPdfExporter pdfExporter;
  final SongChart chart;
  final String songId;

  @override
  State<ChartEditorScreen> createState() => _ChartEditorScreenState();
}

class _ChartEditorScreenState extends State<ChartEditorScreen> {
  late SongChart _chart;
  String? _selectedNoteId;
  late bool _showTitle;
  late bool _showTab;
  late bool _showNotation;
  double _leadVocalContrast = 0.38;
  bool _exporting = false;
  int _selectedMeasureIndex = 0;
  final SemanticUndoHistory _history = SemanticUndoHistory();
  late final DebouncedSemanticAutosaver _autosaver;

  @override
  void initState() {
    super.initState();
    _chart = widget.chart;
    _selectedNoteId = _chart.measures.first.notes.firstOrNull?.id;
    _autosaver = DebouncedSemanticAutosaver(
      save: _saveChart,
      onError: (error, _) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Autosave failed: $error')));
      },
    );
    _showTitle = widget.preferences.showTitle;
    _showTab = widget.preferences.showTab;
    _showNotation = widget.preferences.showNotation;
  }

  Future<void> _saveChart(SongChart chart) {
    return widget.repository.saveSemanticChart(
      chart,
      songId: widget.songId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _commitChart(SongChart chart) {
    _history.record(_chart);
    setState(() => _chart = chart);
    _autosaver.schedule(chart);
  }

  void _undo() {
    final prior = _history.undo();
    if (prior == null) return;
    setState(() {
      _chart = prior;
      if (_selectedMeasureIndex >= _chart.measures.length) {
        _selectedMeasureIndex = _chart.measures.length - 1;
      }
      if (_selectedNoteId != null &&
          _chart.noteById(_selectedNoteId!) == null) {
        _selectedNoteId = null;
      }
    });
    _autosaver.schedule(prior);
  }

  @override
  void dispose() {
    unawaited(_autosaver.dispose());
    super.dispose();
  }

  void _updateDisplay({bool? showTitle, bool? showTab, bool? showNotation}) {
    setState(() {
      _showTitle = showTitle ?? _showTitle;
      _showTab = showTab ?? _showTab;
      _showNotation = showNotation ?? _showNotation;
    });
    widget.onPreferencesChanged(
      widget.preferences.copyWith(
        showTitle: _showTitle,
        showTab: _showTab,
        showNotation: _showNotation,
      ),
    );
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await widget.pdfExporter.exportSemanticWithPicker(
        _chart,
        showTitle: _showTitle,
        showTab: _showTab,
        showNotation: _showNotation,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported $path')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('The semantic PDF could not be created: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _editRest(RestEvent rest) async {
    var position = rest.position;
    var value = rest.value;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit rest'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<BeatFraction>(
                initialValue: position,
                decoration: const InputDecoration(labelText: 'Beat position'),
                items: [
                  for (final beat in <BeatFraction>{
                    position,
                    for (var step = 0; step < 16; step += 1)
                      BeatFraction(step, 4),
                  }.toList()..sort())
                    DropdownMenuItem(value: beat, child: Text(beat.toString())),
                ],
                onChanged: (next) {
                  if (next != null) {
                    setDialogState(() => position = next);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<NoteValue>(
                initialValue: value,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: [
                  for (final option in NoteValue.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (next) {
                  if (next != null) setDialogState(() => value = next);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final measure = _chart.measures[_selectedMeasureIndex];
    _commitChart(
      _chart.replaceMeasure(
        _selectedMeasureIndex,
        measure.copyWith(
          rests: [
            for (final current in measure.rests)
              if (current.id == rest.id)
                RestEvent(
                  id: current.id,
                  position: position,
                  value: value,
                  voice: current.voice,
                  dots: current.dots,
                  tuplet: current.tuplet,
                  verification: current.verification,
                  confidence: current.confidence,
                  sourceMapping: current.sourceMapping,
                )
              else
                current,
          ],
        ),
      ),
    );
  }

  void _applyTuning(BassTuning tuning) {
    final highestString = _chart.measures
        .expand((measure) => measure.notes)
        .fold<int>(
          -1,
          (value, note) => value > note.stringIndex ? value : note.stringIndex,
        );
    if (highestString >= tuning.strings.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Move notes off the strings that would be removed before changing tuning.',
          ),
        ),
      );
      return;
    }
    _commitChart(_chart.copyWith(tuning: tuning));
  }

  Future<void> _editStringTunings() async {
    var name = _chart.tuning.name;
    final strings = [
      for (final string in _chart.tuning.strings)
        (name: string.name, midiPitch: string.midiPitch),
    ];
    final minimumStrings = _chart.measures
        .expand((measure) => measure.notes)
        .fold<int>(
          0,
          (value, note) =>
              value > note.stringIndex + 1 ? value : note.stringIndex + 1,
        );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit individual string tunings'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(labelText: 'Tuning name'),
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < strings.length; index += 1)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('string-name-$index'),
                            initialValue: strings[index].name,
                            decoration: InputDecoration(
                              labelText: 'String ${index + 1}',
                            ),
                            onChanged: (value) {
                              strings[index] = (
                                name: value,
                                midiPitch: strings[index].midiPitch,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            key: ValueKey('string-pitch-$index'),
                            initialValue: strings[index].midiPitch.toString(),
                            decoration: const InputDecoration(
                              labelText: 'Open MIDI',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              strings[index] = (
                                name: strings[index].name,
                                midiPitch:
                                    int.tryParse(value) ??
                                    strings[index].midiPitch,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: strings.length >= 8
                            ? null
                            : () => setDialogState(
                                () => strings.add((
                                  name: 'New',
                                  midiPitch: strings.last.midiPitch - 5,
                                )),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add string'),
                      ),
                      OutlinedButton.icon(
                        onPressed: strings.length <= minimumStrings
                            ? null
                            : () => setDialogState(strings.removeLast),
                        icon: const Icon(Icons.remove),
                        label: const Text('Remove lowest string'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply tuning'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    _applyTuning(
      BassTuning(
        name: name.trim().isEmpty ? 'Custom tuning' : name.trim(),
        strings: [
          for (final string in strings)
            StringTuning(
              name: string.name.trim().isEmpty ? '?' : string.name.trim(),
              midiPitch: string.midiPitch.clamp(0, 127),
            ),
        ],
      ),
    );
  }

  Future<void> _addSection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add section'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Section name',
            hintText: 'Verse 1',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    _commitChart(
      _chart.copyWith(
        sections: [
          ..._chart.sections,
          SongSection(
            id: 'section-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            measureIndex: _selectedMeasureIndex,
          ),
        ],
      ),
    );
  }

  void _addRepeat() {
    _commitChart(
      _chart.copyWith(
        repeats: [
          ..._chart.repeats,
          RepeatRegion(
            id: 'repeat-${DateTime.now().microsecondsSinceEpoch}',
            startMeasureIndex: _selectedMeasureIndex,
            endMeasureIndex: _selectedMeasureIndex,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedNote = _selectedNoteId == null
        ? null
        : _chart.noteById(_selectedNoteId!);
    return Scaffold(
      appBar: AppBar(
        title: Text(_chart.title),
        actions: [
          IconButton(
            tooltip: 'Undo semantic edit',
            onPressed: _history.canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Export semantic A4 PDF',
            onPressed: _exporting ? null : _exportPdf,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
          IconButton(
            tooltip: widget.preferences.appTheme == AppThemePreference.dark
                ? 'Use light theme'
                : 'Use dark theme',
            onPressed: () => widget.onPreferencesChanged(
              widget.preferences.copyWith(
                appTheme: widget.preferences.appTheme == AppThemePreference.dark
                    ? AppThemePreference.light
                    : AppThemePreference.dark,
              ),
            ),
            icon: Icon(
              widget.preferences.appTheme == AppThemePreference.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Title & artist'),
                selected: _showTitle,
                onSelected: (value) => _updateDisplay(showTitle: value),
              ),
              FilterChip(
                label: const Text('Tablature'),
                selected: _showTab,
                onSelected: (value) => _updateDisplay(showTab: value),
              ),
              FilterChip(
                label: const Text('Standard notation'),
                selected: _showNotation,
                onSelected: (value) => _updateDisplay(showNotation: value),
              ),
              Chip(
                avatar: const Icon(Icons.tune, size: 18),
                label: Text(_chart.tuning.name),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InstrumentEditor(
            chart: _chart,
            onTuningChanged: _applyTuning,
            onEditStrings: _editStringTunings,
            onCapoChanged: (capo) => _commitChart(_chart.copyWith(capo: capo)),
          ),
          const SizedBox(height: 10),
          _StructureEditor(
            chart: _chart,
            selectedMeasureIndex: _selectedMeasureIndex,
            onAddSection: _addSection,
            onRemoveSection: (id) => _commitChart(
              _chart.copyWith(
                sections: _chart.sections
                    .where((section) => section.id != id)
                    .toList(),
              ),
            ),
            onAddRepeat: _addRepeat,
            onRepeatChanged: (replacement) => _commitChart(
              _chart.copyWith(
                repeats: [
                  for (final repeat in _chart.repeats)
                    if (repeat.id == replacement.id) replacement else repeat,
                ],
              ),
            ),
            onRemoveRepeat: (id) => _commitChart(
              _chart.copyWith(
                repeats: _chart.repeats
                    .where((repeat) => repeat.id != id)
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MeasureToolbar(
            chart: _chart,
            selectedMeasureIndex: _selectedMeasureIndex,
            onMeasureSelected: (index) =>
                setState(() => _selectedMeasureIndex = index),
            onAddNote: () {
              final note = TabNote.exact(
                id: 'note-${DateTime.now().microsecondsSinceEpoch}',
                position: BeatFraction.zero,
                stringIndex: 0,
                fret: 0,
                value: NoteValue.quarter,
              );
              _selectedNoteId = note.id;
              _commitChart(_chart.addNote(_selectedMeasureIndex, note));
            },
            onAddRest: () {
              final rest = RestEvent(
                id: 'rest-${DateTime.now().microsecondsSinceEpoch}',
                position: BeatFraction.zero,
                value: NoteValue.quarter,
              );
              _commitChart(_chart.addRest(_selectedMeasureIndex, rest));
            },
            onEditRest: _editRest,
            onDeleteRest: (id) => _commitChart(_chart.removeRest(id)),
            onAddMeasure: () {
              _commitChart(
                _chart.addMeasure(
                  ChartMeasure(
                    number: _chart.measures.length + 1,
                    notes: const [],
                  ),
                ),
              );
              setState(
                () => _selectedMeasureIndex = _chart.measures.length - 1,
              );
            },
            onDeleteMeasure: _chart.measures.length <= 1
                ? null
                : () {
                    _commitChart(_chart.removeMeasure(_selectedMeasureIndex));
                    setState(() {
                      _selectedMeasureIndex = _selectedMeasureIndex.clamp(
                        0,
                        _chart.measures.length - 1,
                      );
                      _selectedNoteId = null;
                    });
                  },
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 940,
                child: TabChartView(
                  chart: _chart,
                  showTitle: _showTitle,
                  showTab: _showTab,
                  showNotation: _showNotation,
                  selectedNoteId: _selectedNoteId,
                  leadVocalContrast: _leadVocalContrast,
                  onNoteSelected: (id) => setState(() => _selectedNoteId = id),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final panels = [
                _NoteEditor(
                  note: selectedNote,
                  tuning: _chart.tuning,
                  onChanged: (note) {
                    _commitChart(_chart.replaceNote(note));
                  },
                  onDelete: selectedNote == null
                      ? null
                      : () {
                          _commitChart(_chart.removeNote(selectedNote.id));
                          setState(() => _selectedNoteId = null);
                        },
                ),
                _BackingVocalEditor(
                  chart: _chart,
                  leadVocalContrast: _leadVocalContrast,
                  onContrastChanged: (value) =>
                      setState(() => _leadVocalContrast = value),
                  onLyricChanged: (lyric) {
                    _commitChart(_chart.replaceLyric(lyric));
                  },
                ),
              ];
              if (constraints.maxWidth >= 850) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: panels[0]),
                    const SizedBox(width: 16),
                    Expanded(child: panels[1]),
                  ],
                );
              }
              return Column(
                children: [panels[0], const SizedBox(height: 16), panels[1]],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InstrumentEditor extends StatelessWidget {
  const _InstrumentEditor({
    required this.chart,
    required this.onTuningChanged,
    required this.onEditStrings,
    required this.onCapoChanged,
  });

  final SongChart chart;
  final ValueChanged<BassTuning> onTuningChanged;
  final VoidCallback onEditStrings;
  final ValueChanged<int> onCapoChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instrument and tuning',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onTuningChanged(BassTuning.beadg),
                  child: const Text('Use BEADG'),
                ),
                OutlinedButton(
                  onPressed: () => onTuningChanged(BassTuning.eadg),
                  child: const Text('Use EADG'),
                ),
                OutlinedButton.icon(
                  onPressed: onEditStrings,
                  icon: const Icon(Icons.tune),
                  label: const Text('Edit individual strings'),
                ),
                Chip(
                  label: Text(
                    '${chart.tuning.name} • ${chart.tuning.strings.length} strings',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Capo ${chart.capo}'),
            Slider(
              value: chart.capo.toDouble(),
              min: 0,
              max: 12,
              divisions: 12,
              label: chart.capo.toString(),
              onChanged: (value) => onCapoChanged(value.round()),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructureEditor extends StatelessWidget {
  const _StructureEditor({
    required this.chart,
    required this.selectedMeasureIndex,
    required this.onAddSection,
    required this.onRemoveSection,
    required this.onAddRepeat,
    required this.onRepeatChanged,
    required this.onRemoveRepeat,
  });

  final SongChart chart;
  final int selectedMeasureIndex;
  final VoidCallback onAddSection;
  final ValueChanged<String> onRemoveSection;
  final VoidCallback onAddRepeat;
  final ValueChanged<RepeatRegion> onRepeatChanged;
  final ValueChanged<String> onRemoveRepeat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Song structure',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onAddSection,
                  icon: const Icon(Icons.label_outline),
                  label: Text(
                    'Add section at measure ${selectedMeasureIndex + 1}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAddRepeat,
                  icon: const Icon(Icons.repeat),
                  label: Text(
                    'Add repeat at measure ${selectedMeasureIndex + 1}',
                  ),
                ),
                for (final section in chart.sections)
                  InputChip(
                    label: Text(
                      '${section.name} • measure ${section.measureIndex + 1}',
                    ),
                    onDeleted: () => onRemoveSection(section.id),
                  ),
              ],
            ),
            for (final repeat in chart.repeats)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Repeat ${chart.repeats.indexOf(repeat) + 1}'),
                    DropdownButton<int>(
                      value: repeat.startMeasureIndex,
                      items: _measureItems(chart),
                      onChanged: (value) {
                        if (value == null) return;
                        onRepeatChanged(
                          RepeatRegion(
                            id: repeat.id,
                            startMeasureIndex: value,
                            endMeasureIndex: repeat.endMeasureIndex < value
                                ? value
                                : repeat.endMeasureIndex,
                            times: repeat.times,
                            endings: repeat.endings,
                          ),
                        );
                      },
                    ),
                    const Text('to'),
                    DropdownButton<int>(
                      value: repeat.endMeasureIndex,
                      items: _measureItems(chart)
                          .where(
                            (item) => item.value! >= repeat.startMeasureIndex,
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        onRepeatChanged(
                          RepeatRegion(
                            id: repeat.id,
                            startMeasureIndex: repeat.startMeasureIndex,
                            endMeasureIndex: value,
                            times: repeat.times,
                            endings: repeat.endings,
                          ),
                        );
                      },
                    ),
                    DropdownButton<int>(
                      value: repeat.times,
                      items: [
                        for (var times = 2; times <= 8; times += 1)
                          DropdownMenuItem(
                            value: times,
                            child: Text('$times×'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        onRepeatChanged(
                          RepeatRegion(
                            id: repeat.id,
                            startMeasureIndex: repeat.startMeasureIndex,
                            endMeasureIndex: repeat.endMeasureIndex,
                            times: value,
                            endings: repeat.endings,
                          ),
                        );
                      },
                    ),
                    OutlinedButton(
                      onPressed: repeat.endings.length >= repeat.times
                          ? null
                          : () => onRepeatChanged(
                              RepeatRegion(
                                id: repeat.id,
                                startMeasureIndex: repeat.startMeasureIndex,
                                endMeasureIndex: repeat.endMeasureIndex,
                                times: repeat.times,
                                endings: [
                                  ...repeat.endings,
                                  RepeatEnding(
                                    numbers: [repeat.endings.length + 1],
                                    startMeasureIndex: repeat.endMeasureIndex,
                                    endMeasureIndex: repeat.endMeasureIndex,
                                  ),
                                ],
                              ),
                            ),
                      child: const Text('Add ending'),
                    ),
                    for (final ending in repeat.endings)
                      InputChip(
                        label: Text(
                          'Ending ${ending.numbers.join(',')} at ${ending.startMeasureIndex + 1}',
                        ),
                        onDeleted: () => onRepeatChanged(
                          RepeatRegion(
                            id: repeat.id,
                            startMeasureIndex: repeat.startMeasureIndex,
                            endMeasureIndex: repeat.endMeasureIndex,
                            times: repeat.times,
                            endings: repeat.endings
                                .where((item) => item != ending)
                                .toList(),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Delete repeat',
                      onPressed: () => onRemoveRepeat(repeat.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<int>> _measureItems(SongChart chart) => [
    for (var index = 0; index < chart.measures.length; index += 1)
      DropdownMenuItem(value: index, child: Text('Measure ${index + 1}')),
  ];
}

class _MeasureToolbar extends StatelessWidget {
  const _MeasureToolbar({
    required this.chart,
    required this.selectedMeasureIndex,
    required this.onMeasureSelected,
    required this.onAddNote,
    required this.onAddRest,
    required this.onEditRest,
    required this.onDeleteRest,
    required this.onAddMeasure,
    required this.onDeleteMeasure,
  });

  final SongChart chart;
  final int selectedMeasureIndex;
  final ValueChanged<int> onMeasureSelected;
  final VoidCallback onAddNote;
  final VoidCallback onAddRest;
  final ValueChanged<RestEvent> onEditRest;
  final ValueChanged<String> onDeleteRest;
  final VoidCallback onAddMeasure;
  final VoidCallback? onDeleteMeasure;

  @override
  Widget build(BuildContext context) {
    final measure = chart.measures[selectedMeasureIndex];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: selectedMeasureIndex,
              items: [
                for (var index = 0; index < chart.measures.length; index += 1)
                  DropdownMenuItem(
                    value: index,
                    child: Text('Measure ${chart.measures[index].number}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onMeasureSelected(value);
              },
            ),
            OutlinedButton.icon(
              onPressed: onAddNote,
              icon: const Icon(Icons.music_note),
              label: const Text('Add note'),
            ),
            OutlinedButton.icon(
              onPressed: onAddRest,
              icon: const Icon(Icons.pause),
              label: const Text('Add rest'),
            ),
            OutlinedButton.icon(
              onPressed: onAddMeasure,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add measure'),
            ),
            OutlinedButton.icon(
              onPressed: onDeleteMeasure,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete measure'),
            ),
            for (final rest in measure.rests)
              InputChip(
                label: Text('Rest ${rest.position} (${rest.value.label})'),
                onPressed: () => onEditRest(rest),
                onDeleted: () => onDeleteRest(rest.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteEditor extends StatelessWidget {
  const _NoteEditor({
    required this.note,
    required this.tuning,
    required this.onChanged,
    required this.onDelete,
  });

  final TabNote? note;
  final BassTuning tuning;
  final ValueChanged<TabNote> onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final current = note;
    final beatPositions =
        current == null
              ? const <BeatFraction>[]
              : <BeatFraction>{
                  current.position,
                  for (var step = 0; step < 16; step += 1)
                    BeatFraction(step, 4),
                }.toList()
          ..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: current == null
            ? const Text('Click a fret number to edit the note.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected note',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: current.stringIndex,
                    decoration: const InputDecoration(labelText: 'String'),
                    items: [
                      for (
                        var index = 0;
                        index < tuning.strings.length;
                        index++
                      )
                        DropdownMenuItem(
                          value: index,
                          child: Text(tuning.strings[index].name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onChanged(current.copyWith(stringIndex: value));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Fret ${current.fret}'),
                  Slider(
                    value: current.fret.toDouble(),
                    min: 0,
                    max: 24,
                    divisions: 24,
                    label: current.fret.toString(),
                    onChanged: (value) =>
                        onChanged(current.copyWith(fret: value.round())),
                  ),
                  Text(
                    'Sounding MIDI pitch: ${current.midiPitch(tuning)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BeatFraction>(
                    initialValue: current.position,
                    decoration: const InputDecoration(
                      labelText: 'Beat position',
                    ),
                    items: [
                      for (final position in beatPositions)
                        DropdownMenuItem(
                          value: position,
                          child: Text(position.toString()),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onChanged(current.copyWith(position: value));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Duration',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final value in NoteValue.values)
                        ChoiceChip(
                          label: Text(value.label),
                          selected: current.value == value,
                          onSelected: (_) =>
                              onChanged(current.copyWith(value: value)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Techniques',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final kind in TechniqueKind.values)
                        FilterChip(
                          label: Text(_techniqueLabel(kind)),
                          selected: current.techniques.any(
                            (technique) => technique.kind == kind,
                          ),
                          onSelected: (selected) {
                            final retained = current.techniques
                                .where((technique) => technique.kind != kind)
                                .toList();
                            onChanged(
                              current.copyWith(
                                techniques: [
                                  ...retained,
                                  if (selected) TechniqueMark(kind),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete selected note'),
                  ),
                ],
              ),
      ),
    );
  }

  String _techniqueLabel(TechniqueKind kind) => switch (kind) {
    TechniqueKind.slide => 'Slide',
    TechniqueKind.bend => 'Bend',
    TechniqueKind.hammerOn => 'Hammer-on',
    TechniqueKind.pullOff => 'Pull-off',
    TechniqueKind.naturalHarmonic => 'Natural harmonic',
    TechniqueKind.artificialHarmonic => 'Artificial harmonic',
    TechniqueKind.deadNote => 'Dead note',
    TechniqueKind.palmMute => 'Palm mute',
    TechniqueKind.letRing => 'Let ring',
    TechniqueKind.accent => 'Accent',
  };
}

class _BackingVocalEditor extends StatelessWidget {
  const _BackingVocalEditor({
    required this.chart,
    required this.leadVocalContrast,
    required this.onContrastChanged,
    required this.onLyricChanged,
  });

  final SongChart chart;
  final double leadVocalContrast;
  final ValueChanged<double> onContrastChanged;
  final ValueChanged<LyricSyllable> onLyricChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backing vocal mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Main vocal contrast ${(leadVocalContrast * 100).round()}%'),
            Slider(
              value: leadVocalContrast,
              min: 0.12,
              max: 1,
              onChanged: onContrastChanged,
            ),
            const Divider(),
            for (final lyric in chart.lyrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: lyric.isBackingVocal,
                      onChanged: (value) => onLyricChanged(
                        lyric.copyWith(isBackingVocal: value ?? false),
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey(lyric.id),
                        initialValue: lyric.text,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        onChanged: (text) =>
                            onLyricChanged(lyric.copyWith(text: text)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String?>(
                        initialValue: lyric.alignedNoteId,
                        decoration: const InputDecoration(
                          labelText: 'Aligned note',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final note
                              in chart.measures[lyric.measureIndex].notes)
                            DropdownMenuItem<String?>(
                              value: note.id,
                              child: Text(
                                '${chart.tuning.strings[note.stringIndex].name}${note.fret}',
                              ),
                            ),
                        ],
                        onChanged: (noteId) => onLyricChanged(
                          lyric.copyWith(
                            alignedNoteId: noteId,
                            clearAlignedNote: noteId == null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
