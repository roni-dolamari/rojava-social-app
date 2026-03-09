import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Midnight (Dark) Theme ────────────────────────────────────────────────
  // The original indigo-purple direction, but deeper and richer.
  // Darker background, more saturated primary, warmer purple secondary.

  static const midnightPrimary = Color(0xFF6C76FF); // Rich electric indigo
  static const midnightSecondary = Color(0xFF9F6FFF); // Warm vivid violet
  static const midnightBackground = Color(0xFF0C0E1A); // Deep ink-black navy
  static const midnightSurface = Color(0xFF141728); // Rich dark card
  static const midnightAccent = Color(0xFFB79FFF); // Soft lavender glow

  // ─── Horizon (Light) Theme ───────────────────────────────────────────────
  // Crisp white with a bold indigo primary and violet secondary.
  // More saturated and confident than the original.

  static const horizonPrimary = Color(0xFF4B64F5); // Bold royal indigo
  static const horizonSecondary = Color(0xFF8B6FFF); // Warm violet
  static const horizonBackground = Color(0xFFF3F4FB); // Cool blue-tinted white
  static const horizonSurface = Color(0xFFFFFFFF); // Pure white
  static const horizonAccent = Color(0xFF6C76FF); // Electric indigo

  // ─── Semantic Aliases ────────────────────────────────────────────────────
  static const primary = Color(0xFF5B6EFF); // Vivid indigo-blue
  static const primaryLight = Color(0xFF8B9FFF); // Soft periwinkle
  static const background = Color(0xFFF3F4FB); // Cool blue-tinted white
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E6F5); // Indigo-tinted border

  // ─── Common ──────────────────────────────────────────────────────────────
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  // ─── Text (Dark Theme) ───────────────────────────────────────────────────
  static const textPrimary = Color(0xFFEEEFF8); // Cool near-white
  static const textSecondary = Color(0xFF8B93C4); // Muted lavender-grey
  static const textTertiary = Color(0xFF555E96); // Deeper muted indigo
  static const textHint = Color(0xFF2E3460); // Very subtle indigo

  // ─── Text (Light Theme) ──────────────────────────────────────────────────
  static const textPrimaryLight = Color(0xFF0F1133); // Deep ink navy
  static const textSecondaryLight = Color(0xFF424B8A); // Medium indigo
  static const textHintLight = Color(0xFF8B93C4); // Muted lavender

  // ─── Dividers / Borders ──────────────────────────────────────────────────
  static const divider = Color(0xFF1C2148); // Dark indigo divider
  static const dividerLight = Color(0xFFE4E6F5); // Cool blue-tinted divider
  static const borderLight = Color(0xFFE4E6F5);

  // ─── Semantic Status ─────────────────────────────────────────────────────
  static const error = Color(0xFFFF5370); // Vivid coral-red
  static const success = Color(0xFF17C27A); // Fresh emerald green
  static const warning = Color(0xFFFFAD3B); // Warm amber
  static const info = Color(0xFF3B9EFF); // Clear sky blue

  // ─── Chart / Data Visualization ──────────────────────────────────────────
  static const chartPurple = Color(0xFF9F6FFF); // Vivid violet
  static const chartBlue = Color(0xFF3B9EFF); // Sky blue
  static const chartGreen = Color(0xFF17C27A); // Emerald
  static const chartAmber = Color(0xFFFFAD3B); // Amber

  // ─── Onboarding ──────────────────────────────────────────────────────────
  static const onboardingPink = Color(0xFFFF6B9D); // Rose pink
  static const onboardingBlue = Color(0xFF3B9EFF); // Sky blue
  static const onboardingGreen = Color(0xFF17C27A); // Emerald
  static const onboardingPurple = Color(0xFF9F6FFF); // Violet
}
