import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/features/onboarding/controllers/widgets/onboarding_content.dart';
import 'package:rojava/features/onboarding/controllers/widgets/theme_selection_screen.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../data/repositories/onboarding_repository.dart';
import '../controllers/onboarding_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late PageController _pageController;
  final List<dynamic> _pages = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    final onboardingPages = OnboardingRepository.getOnboardingPages();

    for (int i = 0; i < 4; i++) {
      _pages.add(onboardingPages[i]);
    }

    _pages.add('theme_selection');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_pageController.page! < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skipOnboarding() {
    _pageController.jumpToPage(_pages.length - 1);
  }

  Future<void> _completeOnboarding() async {
    await ref.read(onboardingControllerProvider.notifier).completeOnboarding();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);
    final currentPageIndex = onboardingState.currentPage;
    final isLastPage = currentPageIndex == _pages.length - 1;

    List<Color> backgroundColors = [
      const Color(0xFF1A1A2E),
      const Color(0xFF0F0F1E),
    ];

    if (currentPageIndex < _pages.length - 1) {
      final page = _pages[currentPageIndex];
      if (page is String && page == 'theme_selection') {
        backgroundColors = [const Color(0xFF0F172A), const Color(0xFF1E293B)];
      } else {
        backgroundColors = [
          page.primaryColor.withOpacity(0.2),
          const Color(0xFF0F0F1E),
        ];
      }
    }

    return Scaffold(
      body: GradientBackground(
        colors: backgroundColors,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.onboardingPurple,
                                AppColors.onboardingPink,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.chat_bubble,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          AppStrings.appName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    if (!isLastPage)
                      TextButton(
                        onPressed: _skipOnboarding,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            AppStrings.skip,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    ref
                        .read(onboardingControllerProvider.notifier)
                        .setPage(index);
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];

                    if (page is String && page == 'theme_selection') {
                      return const ThemeSelectionScreen();
                    }

                    return OnboardingContent(page: page);
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    SmoothPageIndicator(
                      controller: _pageController,
                      count: _pages.length,
                      effect: ExpandingDotsEffect(
                        activeDotColor: isLastPage
                            ? AppColors.onboardingGreen
                            : _pages[currentPageIndex] is String
                            ? AppColors.onboardingGreen
                            : _pages[currentPageIndex].primaryColor,
                        dotColor: Colors.white.withOpacity(0.3),
                        dotHeight: 8,
                        dotWidth: 8,
                        expansionFactor: 4,
                        spacing: 8,
                      ),
                    ),

                    const SizedBox(height: 32),

                    if (isLastPage)
                      Column(
                        children: [
                          CustomButton(
                            text: AppStrings.getStarted,
                            onPressed: _completeOnboarding,
                            gradientColors: const [
                              AppColors.onboardingGreen,
                              Color(0xFF33F0D1),
                            ],
                            width: double.infinity,
                            icon: const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                AppStrings.alreadyHaveAccount,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                              TextButton(
                                onPressed: _completeOnboarding,
                                child: const Text(
                                  AppStrings.signIn,
                                  style: TextStyle(
                                    color: AppColors.onboardingGreen,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      CustomButton(
                        text: '',
                        onPressed: _nextPage,
                        width: 64,
                        height: 64,
                        borderRadius: 32,
                        gradientColors: _pages[currentPageIndex] is String
                            ? [
                                AppColors.onboardingGreen,
                                const Color(0xFF33F0D1),
                              ]
                            : _pages[currentPageIndex].gradientColors,
                        icon: const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
