import 'package:flutter/material.dart';

import '../../application/service_contracts.dart';
import '../../application/visual_analysis_review_session.dart';
import '../../domain/visual_chart_models.dart';
import '../../domain/visual_tab_transform_models.dart';
import 'visual_analysis_canvas.dart';

class VisualAnalysisRowList extends StatelessWidget {
  const VisualAnalysisRowList({
    super.key,
    required this.library,
    required this.strips,
    required this.analyses,
    required this.rowStates,
    required this.rowErrors,
    required this.currentIndex,
    required this.selectedTokenIds,
    required this.addingNote,
    required this.onRetry,
    required this.onActivateRow,
    required this.onTokenTap,
    required this.onAddNote,
    required this.onManualDragStart,
    required this.onManualDragUpdate,
    required this.onManualDragEnd,
    required this.onManualDragCancel,
  });

  final ChartLibrary library;
  final List<VisualStrip> strips;
  final List<VisualTabAnalysis?> analyses;
  final List<VisualAnalysisRowState> rowStates;
  final Map<int, Object> rowErrors;
  final int currentIndex;
  final Set<String> selectedTokenIds;
  final bool addingNote;
  final ValueChanged<int> onRetry;
  final ValueChanged<int> onActivateRow;
  final void Function(int index, String tokenId) onTokenTap;
  final void Function(int index, Offset position) onAddNote;
  final void Function(int index, String tokenId) onManualDragStart;
  final void Function(int index, String tokenId, Offset normalizedDelta)
  onManualDragUpdate;
  final void Function(int index, String tokenId) onManualDragEnd;
  final void Function(int index, String tokenId) onManualDragCancel;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: strips.length,
      itemBuilder: (context, index) {
        final analysis = analyses[index];
        if (analysis == null) {
          return AnalysisRowPlaceholder(
            key: ValueKey('analysis-placeholder-$index'),
            rowNumber: index + 1,
            strip: strips[index],
            state: rowStates[index],
            error: rowErrors[index],
            onRetry: rowStates[index] == VisualAnalysisRowState.failed
                ? () => onRetry(index)
                : null,
          );
        }
        final confidence = _analysisConfidence(analysis);
        final ambiguities = analysis.systems.fold<int>(
          0,
          (total, system) =>
              total +
              system.tokens
                  .where(
                    (token) =>
                        token.enabled &&
                        (token.kind == VisualTabTokenKind.ambiguous ||
                            token.stringIndex == null),
                  )
                  .length +
              system.connectedNotationRisks
                  .where(
                    (risk) =>
                        risk.side == VisualConnectedComponentSide.unresolved,
                  )
                  .length,
        );
        return Card(
          key: ValueKey('analysis-row-$index'),
          margin: const EdgeInsets.only(bottom: 12),
          color: index == currentIndex
              ? Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: 0.28)
              : null,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onActivateRow(index),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Row ${index + 1}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text('${analysis.systems.length} system(s)'),
                      Text(
                        '${analysis.enabledFretTokenCount} '
                        'fret/dead-note token(s)',
                      ),
                      Text('${(confidence * 100).round()}% confidence'),
                      Text('$ambiguities unresolved'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  VisualAnalysisCanvas(
                    library: library,
                    strip: strips[index],
                    analysis: analysis,
                    selectedTokenIds: index == currentIndex
                        ? selectedTokenIds
                        : const {},
                    addingNote: index == currentIndex && addingNote,
                    onTokenTap: (id) => onTokenTap(index, id),
                    onAddNote: (position) => onAddNote(index, position),
                    onManualDragStart: (id) => onManualDragStart(index, id),
                    onManualDragUpdate: (id, delta) =>
                        onManualDragUpdate(index, id, delta),
                    onManualDragEnd: (id) => onManualDragEnd(index, id),
                    onManualDragCancel: (id) => onManualDragCancel(index, id),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _analysisConfidence(VisualTabAnalysis analysis) {
    if (analysis.systems.isEmpty) return 0;
    return analysis.systems
            .map((system) => system.confidence)
            .reduce((left, right) => left + right) /
        analysis.systems.length;
  }
}
