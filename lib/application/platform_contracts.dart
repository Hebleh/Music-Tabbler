import '../domain/device_preferences.dart';

abstract interface class DevicePreferencesStore {
  Future<DevicePreferences> load();
  Future<void> save(DevicePreferences preferences);
}

abstract interface class PerformanceModeController {
  Future<void> setActive(bool active);
}

abstract interface class ExternalUrlOpener {
  Future<void> open(String url);
}
