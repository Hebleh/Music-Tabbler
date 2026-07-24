import 'dart:convert';

enum AppThemePreference { light, dark }

enum GigThemePreference { lightOnBlack, darkOnLight }

class DevicePreferences {
  const DevicePreferences({
    this.appTheme = AppThemePreference.dark,
    this.gigTheme = GigThemePreference.lightOnBlack,
    this.showTitle = true,
    this.showTab = true,
    this.showNotation = true,
  });

  static const schemaVersion = 1;
  static const defaults = DevicePreferences();

  final AppThemePreference appTheme;
  final GigThemePreference gigTheme;
  final bool showTitle;
  final bool showTab;
  final bool showNotation;

  DevicePreferences copyWith({
    AppThemePreference? appTheme,
    GigThemePreference? gigTheme,
    bool? showTitle,
    bool? showTab,
    bool? showNotation,
  }) {
    return DevicePreferences(
      appTheme: appTheme ?? this.appTheme,
      gigTheme: gigTheme ?? this.gigTheme,
      showTitle: showTitle ?? this.showTitle,
      showTab: showTab ?? this.showTab,
      showNotation: showNotation ?? this.showNotation,
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'appTheme': appTheme.name,
    'gigTheme': gigTheme.name,
    'showTitle': showTitle,
    'showTab': showTab,
    'showNotation': showNotation,
  };

  String encode() => jsonEncode(toJson());

  factory DevicePreferences.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported device-preference schema: $version');
    }
    return DevicePreferences(
      appTheme: _enumValue(
        AppThemePreference.values,
        json['appTheme'],
        'appTheme',
      ),
      gigTheme: _enumValue(
        GigThemePreference.values,
        json['gigTheme'],
        'gigTheme',
      ),
      showTitle: _boolValue(json, 'showTitle'),
      showTab: _boolValue(json, 'showTab'),
      showNotation: _boolValue(json, 'showNotation'),
    );
  }

  factory DevicePreferences.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Device preferences must be a JSON object.');
    }
    return DevicePreferences.fromJson(decoded.cast<String, Object?>());
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? raw,
    String name,
  ) {
    if (raw is! String) {
      throw FormatException('$name must be a string.');
    }
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('Unknown $name value: $raw');
  }

  static bool _boolValue(Map<String, Object?> json, String name) {
    final value = json[name];
    if (value is bool) return value;
    throw FormatException('$name must be a boolean.');
  }

  @override
  bool operator ==(Object other) =>
      other is DevicePreferences &&
      other.appTheme == appTheme &&
      other.gigTheme == gigTheme &&
      other.showTitle == showTitle &&
      other.showTab == showTab &&
      other.showNotation == showNotation;

  @override
  int get hashCode =>
      Object.hash(appTheme, gigTheme, showTitle, showTab, showNotation);
}
