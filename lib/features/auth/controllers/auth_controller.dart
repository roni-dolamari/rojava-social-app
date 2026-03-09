import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:rojava/data/model/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../../../core/config/supabase_config.dart';

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;
  final bool isBanned;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isBanned = false,
  });

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    String? error,
    bool? isBanned,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isBanned: isBanned ?? this.isBanned,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final AuthService _authService;
  Timer? _banPollTimer;

  AuthController(this._authService) : super(AuthState()) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final currentUser = SupabaseConfig.auth.currentUser;
    if (currentUser != null) {
      try {
        final profile = await _authService.getUserProfile(currentUser.id);
        state = state.copyWith(user: profile);
        _startBanPolling(currentUser.id);
      } catch (e) {
        print('Error checking auth status: $e');
      }
    }
  }

  void _startBanPolling(String userId) {
    _banPollTimer?.cancel();
    _banPollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final response = await SupabaseConfig.client
            .from('profiles')
            .select('is_banned')
            .eq('id', userId)
            .single();

        if (response['is_banned'] == true) {
          await _forceSignOut();
        }
      } catch (e) {
        print('Ban poll error: $e');
      }
    });
  }

  void _stopBanPolling() {
    _banPollTimer?.cancel();
    _banPollTimer = null;
  }

  Future<void> _forceSignOut() async {
    _stopBanPolling();
    await _authService.signOut();
    state = AuthState(isBanned: true, error: 'Your account has been banned.');
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      if (user != null) {
        state = state.copyWith(user: user, isLoading: false);
        _startBanPolling(user.id);
        return true;
      }
      state = state.copyWith(isLoading: false, error: 'Sign up failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.signIn(email: email, password: password);
      if (user != null) {
        state = state.copyWith(user: user, isLoading: false);
        _startBanPolling(user.id);
        return true;
      }
      state = state.copyWith(isLoading: false, error: 'Sign in failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      _stopBanPolling();
      await _authService.signOut();
      state = AuthState();
    } catch (e) {
      print('Sign out error: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _authService.resetPassword(email);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  void resetBanState() {
    if (state.isBanned) {
      state = AuthState();
    }
  }

  @override
  void dispose() {
    _stopBanPolling();
    super.dispose();
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(authServiceProvider)),
);
