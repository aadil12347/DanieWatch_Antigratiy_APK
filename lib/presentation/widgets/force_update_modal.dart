import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/app_update_info.dart';
import '../providers/app_update_provider.dart';

/// A full-screen, non-dismissible blocking overlay that forces the user
/// to update the app before they can use it.
///
/// Dulls the entire screen behind it with a heavy black barrier and shows
/// a centered glassmorphic card with update info and a state-aware button.
class ForceUpdateModal extends ConsumerWidget {
  const ForceUpdateModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(appUpdateStateProvider);
    final info = _extractInfo(updateState);

    if (info == null) return const SizedBox.shrink();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        // Back button does nothing — user must update
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Heavy black barrier — absorbs all taps
            Positioned.fill(
              child: GestureDetector(
                onTap: () {}, // Absorb taps — cannot dismiss
                child: Container(
                  color: Colors.black.withValues(alpha: 0.88),
                ),
              ),
            ),
            // Centered modal card
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _UpdateCard(
                  info: info,
                  state: updateState,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppUpdateInfo? _extractInfo(AppUpdateState state) {
    if (state is AppUpdateReadyToDownload) return state.info;
    if (state is AppUpdateReadyToResume) return state.info;
    if (state is AppUpdateReadyToInstall) return state.info;
    if (state is AppUpdateDownloading) return state.info;
    if (state is AppUpdateDownloadError) return state.info;
    if (state is AppUpdateInstalling) return state.info;
    if (state is AppUpdateNeedsPermission) return state.info;
    return null;
  }
}

/// The glassmorphic card shown inside the modal.
class _UpdateCard extends ConsumerWidget {
  final AppUpdateInfo info;
  final AppUpdateState state;

  const _UpdateCard({required this.info, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 40,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: const Color(0xFFE91E63).withValues(alpha: 0.08),
            blurRadius: 60,
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top gradient accent bar
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated update icon
                  const _AnimatedUpdateIcon(),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    info.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),

                  // Version chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E63).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFE91E63).withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'v${info.version}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE91E63),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    info.description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // File size info (if available)
                  if (info.fileSizeMb != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.storage_rounded,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Download size: ${info.fileSizeMb!.toStringAsFixed(0)} MB',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Error message (if in error state)
                  if (state is AppUpdateDownloadError) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (state as AppUpdateDownloadError).errorMessage,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.error,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Permission message
                  if (state is AppUpdateNeedsPermission) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Please allow DanieWatch to install updates in Settings, then tap the button again.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFFF59E0B),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 8),

                  // State-aware action button
                  _UpdateButton(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated rotating/pulsing update icon.
class _AnimatedUpdateIcon extends StatefulWidget {
  const _AnimatedUpdateIcon();

  @override
  State<_AnimatedUpdateIcon> createState() => _AnimatedUpdateIconState();
}

class _AnimatedUpdateIconState extends State<_AnimatedUpdateIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFE91E63).withValues(alpha: 0.15),
                const Color(0xFFE91E63).withValues(alpha: 0.05),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Transform.rotate(
            angle: _controller.value * 2 * math.pi,
            child: const Icon(
              Icons.system_update_rounded,
              size: 36,
              color: Color(0xFFE91E63),
            ),
          ),
        );
      },
    );
  }
}

/// State-aware action button that transforms based on the current update state.
class _UpdateButton extends ConsumerWidget {
  final AppUpdateState state;

  const _UpdateButton({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: _buildButton(context, ref),
    );
  }

  Widget _buildButton(BuildContext context, WidgetRef ref) {
    return switch (state) {
      AppUpdateReadyToDownload() => _GradientButton(
          label: 'Update Now',
          icon: Icons.download_rounded,
          onTap: () => ref.read(appUpdateStateProvider.notifier).startDownload(),
          gradientColors: const [Color(0xFFE91E63), Color(0xFF9C27B0)],
        ),
      AppUpdateReadyToResume(bytesDownloaded: final bytes, totalBytes: final total) =>
        _GradientButton(
          label: 'Resume Download',
          subtitle: total > 0
              ? '${(bytes / 1024 / 1024).toStringAsFixed(0)} / ${(total / 1024 / 1024).toStringAsFixed(0)} MB'
              : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB downloaded',
          icon: Icons.download_rounded,
          onTap: () => ref.read(appUpdateStateProvider.notifier).startDownload(),
          gradientColors: const [Color(0xFFE91E63), Color(0xFF9C27B0)],
        ),
      AppUpdateDownloading(progress: final progress, receivedBytes: final recv, totalBytes: final total) =>
        _ProgressButton(
          progress: progress,
          label: total > 0
              ? 'Downloading... ${(progress * 100).toInt()}%'
              : 'Downloading... ${(recv / 1024 / 1024).toStringAsFixed(1)} MB',
        ),
      AppUpdateReadyToInstall() => _GradientButton(
          label: 'Install Update',
          icon: Icons.install_mobile_rounded,
          onTap: () => ref.read(appUpdateStateProvider.notifier).startInstall(),
          gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
        ),
      AppUpdateDownloadError() => _GradientButton(
          label: 'Retry Download',
          icon: Icons.refresh_rounded,
          onTap: () => ref.read(appUpdateStateProvider.notifier).startDownload(),
          gradientColors: const [Color(0xFFDC2626), Color(0xFFEF4444)],
        ),
      AppUpdateInstalling() => const _LoadingButton(label: 'Installing...'),
      AppUpdateNeedsPermission() => _GradientButton(
          label: 'Allow & Install',
          icon: Icons.shield_rounded,
          onTap: () => ref.read(appUpdateStateProvider.notifier).startInstall(),
          gradientColors: const [Color(0xFFF59E0B), Color(0xFFEAB308)],
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Gradient action button.
class _GradientButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final List<Color> gradientColors;

  const _GradientButton({
    required this.label,
    this.subtitle,
    required this.icon,
    required this.onTap,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradientColors),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress button with animated fill.
class _ProgressButton extends StatelessWidget {
  final double progress;
  final String label;

  const _ProgressButton({required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE91E63).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Progress fill
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                ),
              ),
            ),
          ),
          // Label
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    value: null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading button with spinner (for "Installing..." state).
class _LoadingButton extends StatelessWidget {
  final String label;

  const _LoadingButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF059669).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
