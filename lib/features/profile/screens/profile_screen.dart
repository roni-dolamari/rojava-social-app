import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:rojava/core/constants/app_theme_type.dart';
import 'package:rojava/features/profile/screens/edit_profile_screen.dart';
import 'package:rojava/core/constants/app_colors.dart';
import '../../../core/constants/app_colors.dart' hide AppColors;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_viewer.dart'; // Add this import
import '../../auth/controllers/auth_controller.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../controllers/profile_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(profileControllerProvider.notifier).loadProfile(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileState = ref.watch(profileControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final selectedTheme = ref.watch(selectedThemeProvider);
    final profile = profileState.profile ?? authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: profileState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 32),

                  // Profile Picture (Tappable to view fullscreen)
                  GestureDetector(
                    onTap: () {
                      if (profile?.avatarUrl != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ImageViewer(
                              imageUrl: profile!.avatarUrl!,
                              heroTag: 'profile_avatar',
                            ),
                          ),
                        );
                      }
                    },
                    child: Hero(
                      tag: 'profile_avatar',
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                        ),
                        child: profile?.avatarUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  profile!.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.person,
                                      size: 60,
                                      color: theme.colorScheme.onPrimary,
                                    );
                                  },
                                ),
                              )
                            : Icon(
                                Icons.person,
                                size: 60,
                                color: theme.colorScheme.onPrimary,
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Profile Info Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoLabel(theme, 'Name'),
                        _buildInfoItem(
                          theme: theme,
                          icon: Icons.person_outline,
                          text: profile?.fullName ?? 'Not set',
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'About',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _buildInfoLabel(theme, 'Email'),
                        _buildInfoItem(
                          theme: theme,
                          icon: Icons.alternate_email,
                          text: profile?.email ?? 'Not set',
                        ),

                        const SizedBox(height: 16),

                        _buildInfoLabel(theme, 'Phone'),
                        _buildInfoItem(
                          theme: theme,
                          icon: Icons.phone_outlined,
                          text: profile?.phone ?? 'Not set',
                        ),

                        const SizedBox(height: 32),

                        // Edit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      EditProfileScreen(profile: profile),
                                ),
                              );
                              if (result == true) {
                                ref
                                    .read(profileControllerProvider.notifier)
                                    .loadProfile();
                              }
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Theme Selection
                        _buildThemeSection(theme, selectedTheme),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoLabel(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required ThemeData theme,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.iconTheme.color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }

  Widget _buildThemeSection(ThemeData theme, AppThemeType selectedTheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00DDB3), Color(0xFF00C9A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.palette, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                'Choose Your Theme',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildThemeCard(
                  theme: theme,
                  label: 'Midnight',
                  // Path to your Moon JSON
                  lottieAsset: 'assets/animations/Moon & Stars.json',
                  colors: [
                    AppColors.midnightPrimary,
                    AppColors.midnightSecondary,
                  ],
                  isSelected: selectedTheme == AppThemeType.midnightGradient,
                  onTap: () {
                    ref
                        .read(onboardingControllerProvider.notifier)
                        .selectTheme(AppThemeType.midnightGradient);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildThemeCard(
                  theme: theme,
                  label: 'Horizon',
                  // Path to your Snowflake JSON
                  lottieAsset:
                      'assets/animations/Snowflake loading screen.json',
                  colors: [
                    AppColors.horizonPrimary,
                    AppColors.horizonSecondary,
                  ],
                  isSelected: selectedTheme == AppThemeType.horizon,
                  onTap: () {
                    ref
                        .read(onboardingControllerProvider.notifier)
                        .selectTheme(AppThemeType.horizon);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard({
    required ThemeData theme,
    required String label,
    required String lottieAsset, // Changed from IconData
    required List<Color> colors,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
        ),
        child: Column(
          children: [
            // Replaced Icon with Lottie.asset
            SizedBox(
              height: 40,
              width: 40,
              child: Lottie.asset(
                lottieAsset,
                repeat: true,
                reverse: true,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 8),
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
