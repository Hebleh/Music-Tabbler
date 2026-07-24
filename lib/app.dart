import 'package:flutter/material.dart';

import 'application/app_services.dart';
import 'features/home/home_screen.dart';
import 'domain/device_preferences.dart';

class MusicTabblerApp extends StatefulWidget {
  const MusicTabblerApp({
    super.key,
    required this.services,
    this.initialPreferences = DevicePreferences.defaults,
  });

  final AppServices services;
  final DevicePreferences initialPreferences;

  @override
  State<MusicTabblerApp> createState() => _MusicTabblerAppState();
}

class _MusicTabblerAppState extends State<MusicTabblerApp> {
  late DevicePreferences _preferences;

  @override
  void initState() {
    super.initState();
    _preferences = widget.initialPreferences;
  }

  Future<void> _updatePreferences(DevicePreferences value) async {
    setState(() => _preferences = value);
    await widget.services.preferences.save(value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Tabbler',
      debugShowCheckedModeBanner: false,
      themeMode: _preferences.appTheme == AppThemePreference.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF315CBA),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8CB4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101216),
        useMaterial3: true,
      ),
      home: HomeScreen(
        services: widget.services,
        preferences: _preferences,
        onPreferencesChanged: _updatePreferences,
      ),
    );
  }
}
