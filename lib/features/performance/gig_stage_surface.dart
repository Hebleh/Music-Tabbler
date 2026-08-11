import 'package:flutter/material.dart';

import '../../application/gig_viewport_layout.dart';
import 'performance_preview_screen.dart';

/// The visual stage surface and its direct pointer/gesture presentation.
///
/// Page selection, toolbar state, and annotation persistence remain owned by
/// the Gig screen and application sessions. This widget only translates stage
/// gestures into those parent callbacks.
class GigStageSurface extends StatelessWidget {
  const GigStageSurface({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.stageLocked,
    required this.toolbarVisible,
    required this.pageDirection,
    required this.annotationTool,
    required this.onToggleToolbar,
    required this.onMove,
    required this.onStrokeCompleted,
    required this.onEraseAt,
  });

  final GigViewportPage page;
  final int pageIndex;
  final double width;
  final double height;
  final bool stageLocked;
  final bool toolbarVisible;
  final int pageDirection;
  final AnnotationTool annotationTool;
  final VoidCallback onToggleToolbar;
  final ValueChanged<int> onMove;
  final PerformanceStrokeCallback onStrokeCompleted;
  final PerformanceEraseCallback onEraseAt;

  @override
  Widget build(BuildContext context) {
    final activeTool = stageLocked ? AnnotationTool.none : annotationTool;
    return Positioned.fill(
      child: GestureDetector(
        key: const Key('gig-stage-surface'),
        behavior: HitTestBehavior.opaque,
        onTap: !stageLocked && annotationTool == AnnotationTool.none
            ? onToggleToolbar
            : null,
        onHorizontalDragEnd:
            (stageLocked || annotationTool == AnnotationTool.none)
            ? (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -250) onMove(1);
                if (velocity > 250) onMove(-1);
              }
            : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8,
            8,
            8,
            stageLocked || !toolbarVisible ? 8 : 174,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(pageDirection * 0.10, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: PerformanceViewportPageView(
              key: ValueKey('gig-page-$pageIndex'),
              page: page,
              width: width,
              height: height,
              annotationTool: activeTool,
              onStrokeCompleted: onStrokeCompleted,
              onEraseAt: onEraseAt,
            ),
          ),
        ),
      ),
    );
  }
}
