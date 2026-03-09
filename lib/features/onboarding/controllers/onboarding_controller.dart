import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:rojava/core/constants/app_theme_type.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingState {
  final int currentPage;
  final AppThemeType selectedTheme;
  final bool isCompleted;

  OnboardingState({
    required this.currentPage,
    required this.selectedTheme,
    required this.isCompleted,
  });

  OnboardingState copyWith({
    int? currentPage,
    AppThemeType? selectedTheme,
    bool? isCompleted,
  }) {
    return OnboardingState(
      currentPage: currentPage ?? this.currentPage,
      selectedTheme: selectedTheme ?? this.selectedTheme,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController()
    : super(
        OnboardingState(
          currentPage: 0,
          selectedTheme: AppThemeType.horizon, // Changed default to Horizon
          isCompleted: false,
        ),
      );

  void setPage(int page) {
    state = state.copyWith(currentPage: page);
  }

  void selectTheme(AppThemeType theme) {
    state = state.copyWith(selectedTheme: theme);
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    await prefs.setString('selected_theme', state.selectedTheme.name);
    state = state.copyWith(isCompleted: true);
  }

  static Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_completed') ?? false;
  }

  static Future<AppThemeType> getSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName =
        prefs.getString('selected_theme') ?? 'horizon'; // Changed default
    return AppThemeType.values.firstWhere(
      (e) => e.name == themeName,
      orElse: () => AppThemeType.horizon, // Changed default
    );
  }
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
      return OnboardingController();
    });

final selectedThemeProvider = Provider<AppThemeType>((ref) {
  return ref.watch(onboardingControllerProvider).selectedTheme;
});
