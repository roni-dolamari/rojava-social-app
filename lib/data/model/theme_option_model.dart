import 'package:flutter/material.dart';
import 'package:rojava/core/constants/app_theme_type.dart';
import '../../core/theme/app_theme.dart';

class ThemeOption {
  final String name;
  final IconData icon;
  final AppThemeType themeType;
  final List<Color> gradientColors;
  final String toastMessage;

  const ThemeOption({
    required this.name,
    required this.icon,
    required this.themeType,
    required this.gradientColors,
    required this.toastMessage,
  });
}
