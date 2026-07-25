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
              Row(
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
                ],
              ),
          ],
        ),
      ),
    );
  }
}
