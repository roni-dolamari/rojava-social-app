import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:rojava/data/model/user_model.dart';
import '../../../data/services/profile_service.dart';

class ProfileState {
  final UserModel? profile;
  final bool isLoading;
  final String? error;

  ProfileState({this.profile, this.isLoading = false, this.error});

  ProfileState copyWith({UserModel? profile, bool? isLoading, String? error}) {
    return ProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ProfileController extends StateNotifier<ProfileState> {
  final ProfileService _profileService;

  ProfileController(this._profileService) : super(ProfileState());

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _profileService.getCurrentProfile();
      state = state.copyWith(profile: profile, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load profile');
    }
  }

  Future<bool> updateProfile({
    required String userId,
    String? fullName,
    String? bio,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _profileService.updateProfile(
        userId: userId,
        fullName: fullName,
        bio: bio,
        phone: phone,
      );

      await loadProfile();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update profile',
      );
      return false;
    }
  }

  Future<bool> uploadProfilePicture({
    required String userId,
    required File imageFile,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _profileService.uploadProfilePicture(
        userId: userId,
        imageFile: imageFile,
      );

      await loadProfile();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to upload image');
      return false;
    }
  }

  Future<bool> deleteProfilePicture(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _profileService.deleteProfilePicture(userId);

      await loadProfile();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to delete image');
      return false;
    }
  }
}

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

final profileControllerProvider =
    StateNotifierProvider<ProfileController, ProfileState>((ref) {
      return ProfileController(ref.watch(profileServiceProvider));
    });
