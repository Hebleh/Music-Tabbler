import 'package:flutter/material.dart';

import '../../application/service_contracts.dart';
import '../../application/visual_deskew.dart';
import '../../domain/visual_chart_models.dart';
import 'visual_strip_preview.dart';

class VisualDeskewDialog extends StatefulWidget {
  const VisualDeskewDialog({
    super.key,
    required this.library,
    required this.strip,
    required this.globalTreatment,
  });

  final ChartLibrary library;
  final VisualStrip strip;
  final VisualTreatment? globalTreatment;

  @override
  State<VisualDeskewDialog> createState() => _VisualDeskewDialogState();
}

class _VisualDeskewDialogState extends State<VisualDeskewDialog> {
  late double _degrees = widget.strip.deskewDegrees;

  VisualStrip get _preview =>
      reprojectVisualStripDeskew(widget.strip, _degrees);

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cancel',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: const Text('Deskew tab row'),
          actions: [
            TextButton(
              onPressed: () => setState(() => _degrees = 0),
              child: const Text('Reset'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, _preview),
              child: const Text('Apply'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Crop and split first, then rotate until the tab strings are '
                  'level. The original image is never changed, and Apply is '
                  'one undoable edit.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: VisualStripPreview(
                        library: widget.library,
                        strip: _preview,
                        globalTreatment: widget.globalTreatment,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('-7°'),
                    Expanded(
                      child: Slider(
                        value: _degrees,
                        min: -maximumDeskewDegrees,
                        max: maximumDeskewDegrees,
                        divisions: 140,
                        label: '${_degrees.toStringAsFixed(1)}°',
                        onChanged: (value) => setState(() => _degrees = value),
                      ),
                    ),
                    const Text('+7°'),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 72,
                      child: Text(
                        '${_degrees.toStringAsFixed(1)}°',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
