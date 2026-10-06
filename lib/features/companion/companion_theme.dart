import 'package:flutter/material.dart';

ThemeData companionTheme({String? fontFamily}) => ThemeData(
  useMaterial3: true,
  fontFamily: fontFamily,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF805A45)),
  scaffoldBackgroundColor: const Color(0xFFFAF7F2),
  inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
  cardTheme: CardThemeData(color: Colors.white, elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48))),
  outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48))),
);
