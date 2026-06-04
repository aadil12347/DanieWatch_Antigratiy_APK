import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../domain/models/manifest_item.dart';
import '../providers/actor_modal_provider.dart';
import '../providers/actor_detail_provider.dart';
import 'movie_card.dart';

/// Actor detail modal content — displayed inside the navbar morphing area.
/// Shows actor bio info + filmography filtered to items in the app's JSON index.
class ActorModalContent extends ConsumerWidget {
  const ActorModalContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modalState = ref.watch(actorModalProvider);
    final actorId = modalState.actorId;
    if (actorId == null) return const SizedBox.shrink();

    final actorInfoAsync = ref.watch(actorInfoProvider(actorId));
    final filmographyAsync = ref.watch(actorFilmographyProvider(actorId));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.77,
      ),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header: Profile + Name + Close ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              children: [
                // Profile image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: modalState.profilePath != null
                        ? CachedNetworkImage(
                            imageUrl:
                                'https://image.tmdb.org/t/p/w185${modalState.profilePath}',
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.person,
                                  color: AppColors.textMuted, size: 28),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.person,
                                  color: AppColors.textMuted, size: 28),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.person,
                                color: AppColors.textMuted, size: 28),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Name + character
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modalState.actorName ?? 'Actor',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (modalState.characterName != null &&
                          modalState.characterName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'as ${modalState.characterName}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Close button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ref.read(actorModalProvider.notifier).state =
                        const ActorModalState();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white70, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Scrollable content ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Actor info section
                  actorInfoAsync.when(
                    loading: () => _buildInfoSkeleton(),
                    error: (e, _) => const SizedBox.shrink(),
                    data: (info) {
                      if (info == null) return const SizedBox.shrink();
                      return _buildInfoSection(info);
                    },
                  ),

                  const SizedBox(height: 20),

                  // Filmography section
                  Text(
                    'Available in DanieWatch',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  filmographyAsync.when(
                    loading: () => _buildFilmographySkeleton(),
                    error: (e, _) => _buildEmptyFilmography(),
                    data: (items) {
                      if (items.isEmpty) return _buildEmptyFilmography();
                      return _buildFilmographyGrid(context, ref, items);
                    },
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Info Section ──────────────────────────────────────────────────────────

  Widget _buildInfoSection(ActorInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info chips row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (info.age != null)
              _buildInfoChip(Icons.cake_outlined, '${info.age} years'),
            if (info.gender != null)
              _buildInfoChip(
                info.gender == 'Female'
                    ? Icons.female_rounded
                    : info.gender == 'Male'
                        ? Icons.male_rounded
                        : Icons.person_outline,
                info.gender!,
              ),
            if (info.country != null)
              _buildInfoChip(Icons.location_on_outlined, info.country!),
            if (info.knownFor != null)
              _buildInfoChip(Icons.movie_outlined, info.knownFor!),
          ],
        ),

        // Biography
        if (info.biography != null && info.biography!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ExpandableBio(text: info.biography!),
        ],
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filmography Grid ─────────────────────────────────────────────────────

  Widget _buildFilmographyGrid(
      BuildContext context, WidgetRef ref, List<ManifestItem> items) {
    final r = Responsive(context);
    final gridSpacing = r.w(12).clamp(8.0, 16.0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: gridSpacing,
        mainAxisSpacing: gridSpacing,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MovieCard(
          key: ValueKey('actor_film_${item.id}_$index'),
          item: item,
          onTap: () {
            // Close modal first, then navigate
            ref.read(actorModalProvider.notifier).state =
                const ActorModalState();
            context.push('/details/${item.mediaType}/${item.id}');
          },
        );
      },
    );
  }

  // ─── Empty / Loading States ───────────────────────────────────────────────

  Widget _buildEmptyFilmography() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.movie_filter_outlined,
                size: 36,
                color: AppColors.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              'No matching titles found',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: Row(
        children: List.generate(
          3,
          (i) => Container(
            margin: const EdgeInsets.only(right: 8),
            width: 80,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilmographySkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.55,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ─── Expandable Biography ────────────────────────────────────────────────────

class _ExpandableBio extends StatefulWidget {
  final String text;
  const _ExpandableBio({required this.text});

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if (widget.text.length > 150)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _expanded ? 'Show Less' : 'Read More',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
