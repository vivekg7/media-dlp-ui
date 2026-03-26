import 'package:flutter/material.dart';

const _seedColor = Color(0xFF6750A4);

final lightTheme = ThemeData(
  colorSchemeSeed: _seedColor,
  brightness: Brightness.light,
  useMaterial3: true,
);

final darkTheme = ThemeData(
  colorSchemeSeed: _seedColor,
  brightness: Brightness.dark,
  useMaterial3: true,
);
