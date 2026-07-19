import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';

void main() {
  runApp(const MusicTabblerApp());
}

class MusicTabblerApp extends StatefulWidget {
  const MusicTabblerApp({super.key});

  @override
  State<MusicTabblerApp> createState() => _MusicTabblerAppState();
}

class _MusicTabblerAppState extends State<MusicTabblerApp> {
  var _isDark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Tabbler',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
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
        isDark: _isDark,
        onToggleTheme: () => setState(() => _isDark = !_isDark),
      ),
    );
  }
}
