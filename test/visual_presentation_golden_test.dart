import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/gig_viewport_layout.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/application/visual_analysis_review_session.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/features/import/visual_analysis_canvas.dart';
import 'package:music_tabbler/features/performance/performance_preview_screen.dart';

void main() {
  group('Windows visual presentation baselines', () {
    testWidgets(
      'gig viewport keeps headers and adjacent rows stage-readable',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final rowBytes = _tabRowPng();
        final page = GigViewportPage(
          index: 0,
          entryId: 'entry',
          items: [
            const GigViewportItem(
              element: PerformanceDeckElement(
                kind: PerformanceElementKind.header,
                entryIndex: 0,
                entryId: 'entry',
                title: 'Stage Song',
                artist: 'Bass Player',
                width: 960,
                height: 54,
              ),
              left: 20,
              top: 16,
              width: 960,
              height: 54,
            ),
            GigViewportItem(
              element: PerformanceDeckElement(
                kind: PerformanceElementKind.strip,
                entryIndex: 0,
                entryId: 'entry',
                sourceStripId: 'row-1',
                rowIndex: 0,
                width: 600,
                height: 100,
                imageBytes: rowBytes,
              ),
              left: 20,
              top: 82,
              width: 470,
              height: 118,
            ),
            GigViewportItem(
              element: PerformanceDeckElement(
                kind: PerformanceElementKind.strip,
                entryIndex: 0,
                entryId: 'entry',
                sourceStripId: 'row-2',
                rowIndex: 1,
                width: 600,
                height: 100,
                imageBytes: rowBytes,
              ),
              left: 510,
              top: 82,
              width: 470,
              height: 118,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: ColoredBox(
                color: Colors.black,
                child: PerformanceViewportPageView(
                  page: page,
                  width: 1000,
                  height: 700,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/windows/gig_viewport.png'),
        );
      },
      skip: !Platform.isWindows,
    );

    testWidgets(
      'analysis placeholders distinguish waiting and failed rows',
      (tester) async {
        tester.view.physicalSize = const Size(900, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const strip = VisualStrip(
          id: 'row',
          assetHash: 'asset',
          assetExtension: 'png',
          pixelWidth: 1200,
          pixelHeight: 180,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    AnalysisRowPlaceholder(
                      rowNumber: 3,
                      strip: strip,
                      state: VisualAnalysisRowState.waiting,
                    ),
                    AnalysisRowPlaceholder(
                      rowNumber: 4,
                      strip: strip,
                      state: VisualAnalysisRowState.failed,
                      error: 'Local OCR could not read this row',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/windows/analysis_placeholders.png'),
        );
      },
      skip: !Platform.isWindows,
    );
  });
}

Uint8List _tabRowPng() {
  final image = img.Image(width: 600, height: 100);
  img.fill(image, color: img.ColorRgb8(250, 250, 248));
  for (var string = 0; string < 5; string += 1) {
    final y = 18 + string * 14;
    img.drawLine(
      image,
      x1: 18,
      y1: y,
      x2: 582,
      y2: y,
      color: img.ColorRgb8(35, 35, 35),
      thickness: 2,
    );
  }
  for (final x in [80, 210, 350, 490]) {
    img.drawLine(
      image,
      x1: x,
      y1: 16,
      x2: x,
      y2: 76,
      color: img.ColorRgb8(45, 45, 45),
      thickness: 2,
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}
