import '../domain/device_preferences.dart';
import 'gig_viewport_layout.dart';

/// Owns Gig Mode navigation and viewport-control state.
///
/// Deck generation and pixel layout remain pure services. This session keeps
/// the interaction invariants (page direction, stage lock, zoom overrides,
/// alignment, theme, and toolbar visibility) out of the widget tree.
class GigViewportSession {
  GigViewportSession({
    required double initialZoom,
    required GigThemePreference initialTheme,
  }) : _setWideZoom = initialZoom,
       _theme = initialTheme;

  int _pageIndex = 0;
  int _pageDirection = 1;
  double _setWideZoom;
  final Map<String, double> _songZoomByEntry = {};
  GigHorizontalAlignment _alignment = GigHorizontalAlignment.left;
  GigThemePreference _theme;
  bool _stageLocked = false;
  bool _toolbarVisible = true;

  int get pageIndex => _pageIndex;
  int get pageDirection => _pageDirection;
  double get setWideZoom => _setWideZoom;
  Map<String, double> get songZoomByEntry =>
      Map<String, double>.unmodifiable(_songZoomByEntry);
  GigHorizontalAlignment get alignment => _alignment;
  GigThemePreference get theme => _theme;
  bool get stageLocked => _stageLocked;
  bool get toolbarVisible => _toolbarVisible;

  double zoomForEntry(String entryId) =>
      _songZoomByEntry[entryId] ?? _setWideZoom;

  void resetPage() => _pageIndex = 0;

  bool selectPage(int target) {
    if (target < 0 || target == _pageIndex) return false;
    _pageDirection = target >= _pageIndex ? 1 : -1;
    _pageIndex = target;
    return true;
  }

  bool move(int delta, int pageCount) {
    if (pageCount <= 0) return false;
    final next = (_pageIndex + delta).clamp(0, pageCount - 1);
    if (next == _pageIndex) return false;
    _pageDirection = delta >= 0 ? 1 : -1;
    _pageIndex = next;
    return true;
  }

  void setSongZoom(String entryId, double value, {required int anchorPage}) {
    _songZoomByEntry[entryId] = value;
    _pageIndex = anchorPage < 0 ? 0 : anchorPage;
  }

  void updateSetWideZoom(double value, {required int anchorPage}) {
    _setWideZoom = value;
    _pageIndex = anchorPage < 0 ? 0 : anchorPage;
  }

  void setAlignment(GigHorizontalAlignment value) => _alignment = value;

  bool setTheme(GigThemePreference value) {
    if (_stageLocked || value == _theme) return false;
    _theme = value;
    return true;
  }

  void toggleToolbar() {
    if (!_stageLocked) _toolbarVisible = !_toolbarVisible;
  }

  void lockStage() {
    _stageLocked = true;
    _toolbarVisible = false;
  }

  void unlockStage() {
    _stageLocked = false;
    _toolbarVisible = true;
  }
}
