import 'package:flutter/material.dart';

class OnboardingPage {
  final String title;
  final String description;
  final String animationPath;
  final Color primaryColor;
  final Color secondaryColor;
  final List<Color> gradientColors;

  const OnboardingPage({
    required this.title,
    required this.description,
    required this.animationPath,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gradientColors,
  });
}
