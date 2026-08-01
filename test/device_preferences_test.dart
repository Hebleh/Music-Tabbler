import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/device_preferences.dart';
import 'package:music_tabbler/infrastructure/device_preferences_store.dart';

void main() {
  late Directory directory;
  late File file;
  late FileDevicePreferencesStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'music-tabbler-preferences-',
    );
    file = File('${directory.path}${Platform.pathSeparator}preferences.json');
    store = FileDevicePreferencesStore(file);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('first install uses dark app and light-on-black gig defaults', () async {
    final preferences = await store.load();

    expect(preferences.appTheme, AppThemePreference.dark);
    expect(preferences.gigTheme, GigThemePreference.lightOnBlack);
    expect(preferences.showTitle, isTrue);
    expect(preferences.showTab, isTrue);
    expect(preferences.showNotation, isTrue);
    expect(preferences.gigZoom, 0.75);
  });

  test('preferences survive a new store instance', () async {
    final saved = DevicePreferences.defaults.copyWith(
      appTheme: AppThemePreference.light,
      gigTheme: GigThemePreference.darkOnLight,
      showTitle: false,
      showNotation: false,
      gigZoom: 0.55,
    );

    await store.save(saved);
    final reopened = await FileDevicePreferencesStore(file).load();

    expect(reopened, saved);
  });

  test('schema-v1 preferences migrate with the default gig zoom', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '{"schemaVersion":1,"appTheme":"dark","gigTheme":"lightOnBlack",'
      '"showTitle":true,"showTab":true,"showNotation":true}',
    );

    final migrated = await store.load();

    expect(migrated.gigZoom, 0.75);
  });

  test('corrupt preferences fall back without changing the file', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{not-json');

    expect(await store.load(), DevicePreferences.defaults);
    expect(await file.readAsString(), '{not-json');
  });

  test('saving replaces corrupt content and cleans staging files', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{not-json');

    await store.save(DevicePreferences.defaults.copyWith(showTab: false));

    expect((await store.load()).showTab, isFalse);
    expect(await File('${file.path}.partial').exists(), isFalse);
    expect(await File('${file.path}.previous').exists(), isFalse);
  });
}
