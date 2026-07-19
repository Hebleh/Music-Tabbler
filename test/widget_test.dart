import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/main.dart';

void main() {
  testWidgets('opens the semantic sample chart from the song pool', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MusicTabblerApp());

    expect(find.text('Song Pool'), findsWidgets);
    expect(find.text('Gigs'), findsOneWidget);
    expect(find.text('New / Import'), findsOneWidget);

    await tester.tap(find.text('Open sample chart'));
    await tester.pumpAndSettle();

    expect(find.text('Foundation Groove'), findsWidgets);
    expect(find.text('Tablature'), findsOneWidget);
    expect(find.text('Standard notation'), findsOneWidget);
    expect(find.text('Backing vocal mode'), findsOneWidget);
  });

  testWidgets('keeps tablature visible when notation is toggled off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MusicTabblerApp());
    await tester.tap(find.text('Open sample chart'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standard notation'));
    await tester.pumpAndSettle();

    final tabChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Tablature'),
    );
    final notationChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Standard notation'),
    );
    expect(tabChip.selected, isTrue);
    expect(notationChip.selected, isFalse);
  });
}
