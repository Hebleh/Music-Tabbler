import 'package:flutter/material.dart';

import '../../domain/music_models.dart';
import '../../domain/device_preferences.dart';
import 'tab_chart_view.dart';

class ChartEditorScreen extends StatefulWidget {
  const ChartEditorScreen({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
  });

  final DevicePreferences preferences;
  final ValueChanged<DevicePreferences> onPreferencesChanged;

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

  @override
  void initState() {
    super.initState();
    _chart = SongChart.foundationExample();
    _selectedNoteId = _chart.measures.first.notes.first.id;
    _showTitle = widget.preferences.showTitle;
    _showTab = widget.preferences.showTab;
    _showNotation = widget.preferences.showNotation;
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
                    setState(() => _chart = _chart.replaceNote(note));
                  },
                ),
                _BackingVocalEditor(
                  chart: _chart,
                  leadVocalContrast: _leadVocalContrast,
                  onContrastChanged: (value) =>
                      setState(() => _leadVocalContrast = value),
                  onLyricChanged: (lyric) {
                    setState(() => _chart = _chart.replaceLyric(lyric));
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

class _NoteEditor extends StatelessWidget {
  const _NoteEditor({
    required this.note,
    required this.tuning,
    required this.onChanged,
  });

  final TabNote? note;
  final BassTuning tuning;
  final ValueChanged<TabNote> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = note;
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
