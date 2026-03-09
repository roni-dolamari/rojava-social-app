import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/core/constants/app_theme_type.dart';
import 'package:rojava/features/home/screen/home_screen.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/onboarding/controllers/onboarding_controller.dart';
import 'features/onboarding/screen/onboarding_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: RojavaApp()));
}

class RojavaApp extends ConsumerStatefulWidget {
  const RojavaApp({Key? key}) : super(key: key);

  @override
  ConsumerState<RojavaApp> createState() => _RojavaAppState();
}

class _RojavaAppState extends ConsumerState<RojavaApp> {
  bool _isLoading = true;
  bool _onboardingCompleted = false;
  AppThemeType _savedTheme = AppThemeType.horizon;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final completed = await OnboardingController.isOnboardingCompleted();
    final theme = await OnboardingController.getSavedTheme();

    final isAuthenticated = SupabaseConfig.auth.currentUser != null;

    setState(() {
      _onboardingCompleted = completed;
      _savedTheme = theme;
      _isLoading = false;
    });

    if (completed) {
      ref.read(onboardingControllerProvider.notifier).selectTheme(theme);
    }

    if (isAuthenticated) {
      ref.read(authControllerProvider.notifier);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      );
    }

    final selectedTheme = ref.watch(selectedThemeProvider);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.isBanned && next.user == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/login',
            (_) => false,
          );
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been banned. Please contact support.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
        });
      }
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: 'ROJAVA',
      theme: AppTheme.getTheme(selectedTheme),
      home: _getInitialScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }

  Widget _getInitialScreen() {
    final isAuthenticated = SupabaseConfig.auth.currentUser != null;

    if (!_onboardingCompleted) {
      return const OnboardingScreen();
    }

    if (isAuthenticated) {
      return const HomeScreen();
    }

    return const LoginScreen();
  }
}
