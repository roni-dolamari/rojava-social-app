import 'package:flutter/material.dart';
import 'package:rojava/core/constants/app_strings.dart';
import 'package:rojava/core/constants/app_theme_type.dart';
import 'package:rojava/data/model/onboarding_page_model.dart';
import 'package:rojava/data/model/theme_option_model.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart' hide AppColors;
// adjust path as neede
import 'package:rojava/core/constants/app_colors.dart';

import '../../core/theme/app_theme.dart';

class OnboardingRepository {
  OnboardingRepository._();

  static List<OnboardingPage> getOnboardingPages() {
    return [
      const OnboardingPage(
        title: AppStrings.connectWithFriends,
        description: AppStrings.connectWithFriendsDesc,
        animationPath: AppAssets.contactUsAnimation,
        primaryColor: AppColors.onboardingPurple,
        secondaryColor: Color(0xFF7C5DFA),
        gradientColors: [Color(0xFF9D5CFF), Color(0xFF7C5DFA)],
      ),
      const OnboardingPage(
        title: AppStrings.shareYourStory,
        description: AppStrings.shareYourStoryDesc,
        animationPath: AppAssets.uploadCloudAnimation,
        primaryColor: AppColors.onboardingPink,
        secondaryColor: Color(0xFFFF8FB1),
        gradientColors: [Color(0xFFFF6B9D), Color(0xFFFF8FB1)],
      ),
      const OnboardingPage(
        title: AppStrings.voiceVideoCalls,
        description: AppStrings.voiceVideoCallsDesc,
        animationPath: AppAssets.callingAnimation,
        primaryColor: AppColors.onboardingBlue,
        secondaryColor: Color(0xFF63A4FF),
        gradientColors: [Color(0xFF4A90E2), Color(0xFF63A4FF)],
      ),
      const OnboardingPage(
        title: AppStrings.aiAssistant,
        description: AppStrings.aiAssistantDesc,
        animationPath: AppAssets.aiRobotAnimation,
        primaryColor: AppColors.onboardingBlue,
        secondaryColor: Color(0xFF63A4FF),
        gradientColors: [Color(0xFF4A90E2), Color(0xFF63A4FF)],
      ),
      const OnboardingPage(
        title: AppStrings.chooseYourTheme,
        description: AppStrings.chooseYourThemeDesc,
        animationPath: '',
        primaryColor: AppColors.onboardingGreen,
        secondaryColor: Color(0xFF33F0D1),
        gradientColors: [Color(0xFF00DDB3), Color(0xFF33F0D1)],
      ),
    ];
  }

  static List<ThemeOption> getThemeOptions() {
    return const [
      ThemeOption(
        name: AppStrings.midnightGradient,
        icon: Icons.nightlight_round,
        themeType: AppThemeType.midnightGradient,
        gradientColors: [
          AppColors.midnightPrimary,
          AppColors.midnightSecondary,
        ],
        toastMessage: AppStrings.switchedToMidnight,
      ),
      ThemeOption(
        name: AppStrings.horizon,
        icon: Icons.wb_sunny,
        themeType: AppThemeType.horizon, // Changed
        gradientColors: [AppColors.horizonPrimary, AppColors.horizonSecondary],
        toastMessage: AppStrings.switchedToHorizon, // Changed
      ),
    ];
  }
}
