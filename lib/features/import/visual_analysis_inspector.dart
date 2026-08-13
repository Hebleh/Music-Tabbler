import 'package:flutter/material.dart';

import '../../domain/visual_tab_transform_models.dart';
import 'visual_analysis_canvas.dart';

class VisualAnalysisInspector extends StatelessWidget {
  const VisualAnalysisInspector({
    super.key,
    required this.analysis,
    required this.selectedTokenIds,
    required this.onToggleToken,
    required this.onSetRiskSide,
    required this.onRemoveRisk,
  });

  final VisualTabAnalysis? analysis;
  final Set<String> selectedTokenIds;
  final ValueChanged<String> onToggleToken;
  final void Function(
    String systemId,
    String riskId,
    VisualConnectedComponentSide side,
  )
  onSetRiskSide;
  final void Function(String systemId, String riskId) onRemoveRisk;

  @override
  Widget build(BuildContext context) {
    final current = analysis;
    return SizedBox(
      width: 330,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (current == null)
                const ListTile(
                  title: Text('Select a completed row to review it.'),
                )
              else ...[
                if (current.warnings.isNotEmpty) ...[
                  for (final warning in current.warnings)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(warning),
                    ),
                  const Divider(),
                ],
                for (final system in current.systems) ...[
                  ListTile(
                    dense: true,
                    title: Text(
                      'System ${current.systems.indexOf(system) + 1}',
                    ),
                    subtitle: Text(
                      '${system.stringLines.length} strings \u00B7 '
                      '${system.barLines.length} bar lines \u00B7 '
                      '${system.connectedNotationRisks.length} seam risk(s)',
                    ),
                  ),
                  if (system.connectedNotationRisks.isNotEmpty)
                    const ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.location_on_outlined,
                        color: Colors.redAccent,
                      ),
                      title: Text('Find the matching red numbered marker.'),
                      subtitle: Text(
                        'Its dashed line shows the seam between two strings.',
                      ),
                    ),
                  for (
                    var riskIndex = 0;
                    riskIndex < system.connectedNotationRisks.length;
                    riskIndex += 1
                  )
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                  VisualConnectedComponentSide
                                >(
                                  isExpanded: true,
                                  initialValue: system
                                      .connectedNotationRisks[riskIndex]
                                      .side,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: visualRiskLocationLabel(
                                      system.connectedNotationRisks[riskIndex],
                                      riskIndex,
                                    ),
                                    helperText:
                                        'Choose which side moves as one piece.',
                                    helperMaxLines: 2,
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
                                      onSetRiskSide(
                                        system.id,
                                        system
                                            .connectedNotationRisks[riskIndex]
                                            .id,
                                        side,
                                      );
                                    }
                                  },
                                ),
                          ),
                          IconButton(
                            tooltip: 'Remove seam marker',
                            onPressed: () => onRemoveRisk(
                              system.id,
                              system.connectedNotationRisks[riskIndex].id,
                            ),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final token in system.tokens)
                    CheckboxListTile(
                      dense: true,
                      value: selectedTokenIds.contains(token.id),
                      onChanged: (_) => onToggleToken(token.id),
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
                        '${token.origin == VisualTabTokenOrigin.manual ? "manual \u00B7 " : ""}'
                        '${token.kind.name} \u00B7 '
                        '${token.stringIndex == null ? "no string" : "string ${token.stringIndex! + 1}"}',
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
