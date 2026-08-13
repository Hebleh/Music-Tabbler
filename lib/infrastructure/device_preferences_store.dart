import 'dart:io';

import '../application/service_contracts.dart';
import '../domain/device_preferences.dart';

class FileDevicePreferencesStore implements DevicePreferencesStore {
  FileDevicePreferencesStore(this.file);

  final File file;

  @override
  Future<DevicePreferences> load() async {
    if (!await file.exists()) return DevicePreferences.defaults;
    try {
      return DevicePreferences.decode(await file.readAsString());
    } on Object {
      return DevicePreferences.defaults;
    }
  }

  @override
  Future<void> save(DevicePreferences preferences) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.partial');
    final previous = File('${file.path}.previous');
    var movedPrevious = false;
    try {
      await temporary.writeAsString(preferences.encode(), flush: true);
      if (await file.exists()) {
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
        movedPrevious = true;
      }
      await temporary.rename(file.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await file.exists() && movedPrevious && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
      if (await previous.exists() && await file.exists()) {
        await previous.delete();
      }
    }
  }
}
