import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class UserAvatar extends ConsumerWidget {
  final double size;
  final bool canEdit;

  const UserAvatar({
    super.key,
    this.size = 48,
    this.canEdit = false,
  });

  /// Generate a consistent random-looking color based on username
  Color _getVibrantColor(String username) {
    final colors = [
      const Color(0xFFE91E63), // Pink
      const Color(0xFF9C27B0), // Purple
      const Color(0xFF673AB7), // Indigo
      const Color(0xFF3F51B5), // Blue
      const Color(0xFF2196F3), // Light Blue
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFF009688), // Teal
      const Color(0xFF4CAF50), // Green
      const Color(0xFFFF9800), // Orange
      const Color(0xFFFF5722), // Deep Orange
    ];
    final index = username.codeUnits.reduce((a, b) => a + b) % colors.length;
    return colors[index];
  }

  Future<void> _handleEdit(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: const Text('Change Profile Picture', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                if (image != null) {
                  await ref.read(profileProvider.notifier).uploadAvatar(image.path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Remove Profile Picture', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(profileProvider.notifier).deleteAvatar();
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: const Text('Logout', style: TextStyle(color: Colors.white70)),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(profileProvider.notifier).signOut();
                // Note: The router redirect will handle navigation back to splash
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final username = profile?.username ?? 'U';
    final avatarUrl = profile?.avatarUrl;

    Widget avatarContent;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarContent = CachedNetworkImage(
        imageUrl: avatarUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: AppColors.surfaceElevated),
        errorWidget: (context, url, error) => _buildLetterFallback(username),
      );
    } else {
      avatarContent = _buildLetterFallback(username);
    }

    return GestureDetector(
      onTap: canEdit ? () => _handleEdit(context, ref) : null,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(child: avatarContent),
          ),
          if (canEdit)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLetterFallback(String username) {
    return Container(
      color: _getVibrantColor(username),
      alignment: Alignment.center,
      child: Text(
        username.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
