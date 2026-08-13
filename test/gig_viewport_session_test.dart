import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/gig_viewport_layout.dart';
import 'package:music_tabbler/application/gig_viewport_session.dart';
import 'package:music_tabbler/domain/device_preferences.dart';

void main() {
  test('gig viewport session preserves navigation and lock invariants', () {
    final session = GigViewportSession(
      initialZoom: 0.75,
      initialTheme: GigThemePreference.lightOnBlack,
    );

    expect(session.move(1, 3), isTrue);
    expect(session.pageIndex, 1);
    expect(session.pageDirection, 1);
    expect(session.move(-1, 3), isTrue);
    expect(session.pageIndex, 0);
    expect(session.pageDirection, -1);

    session.setSongZoom('song-a', 1.1, anchorPage: 2);
    expect(session.zoomForEntry('song-a'), 1.1);
    expect(session.zoomForEntry('song-b'), 0.75);
    expect(session.pageIndex, 2);

    session.updateSetWideZoom(0.9, anchorPage: 1);
    session.setAlignment(GigHorizontalAlignment.right);
    expect(session.setWideZoom, 0.9);
    expect(session.zoomForEntry('song-b'), 0.9);
    expect(session.alignment, GigHorizontalAlignment.right);

    session.lockStage();
    expect(session.stageLocked, isTrue);
    expect(session.toolbarVisible, isFalse);
    expect(session.setTheme(GigThemePreference.darkOnLight), isFalse);
    session.toggleToolbar();
    expect(session.toolbarVisible, isFalse);

    session.unlockStage();
    expect(session.setTheme(GigThemePreference.darkOnLight), isTrue);
    expect(session.theme, GigThemePreference.darkOnLight);
    expect(session.toolbarVisible, isTrue);
  });
}
