import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/download_modal_provider.dart';
import '../../../core/utils/toast_utils.dart';
import '../../widgets/quality_selector_sheet.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/clients/tmdb_client.dart';
import '../../../data/local/download_manager.dart';
import '../../../domain/models/content_detail.dart';
import '../../../domain/models/entry.dart';
import '../../../services/video_extractor_service.dart';
import '../../providers/detail_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/play_loader_overlay.dart';
import '../video_player/video_player_screen.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final int tmdbId;
  final String mediaType;

  const DetailsScreen({
    super.key,
    required this.tmdbId,
    required this.mediaType,
  });

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  int _selectedSeason = 1;
  int _tabIndex = 0; // 0 = Episodes/Similars, 1 = Similars/Reviews, 2 = Reviews/Share, 3 = Share
  String _episodeSearch = '';

  DetailParams get _detailParams =>
      DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType);

  EpisodeParams _getEpisodeParams(ContentDetail? content) =>
      EpisodeParams(
        tmdbId: widget.tmdbId,
        seasonNumber: _selectedSeason,
        seasonsData: content?.seasonsData,
        isAdmin: content?.isAdmin ?? false,
      );

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(detailProvider(_detailParams));
    final isInWatchlist = ref.watch(watchlistProvider).maybeWhen(
          data: (items) => items.any((i) =>
              i.tmdbId == widget.tmdbId && i.mediaType == widget.mediaType),
          orElse: () => false,
        );

    return detailAsync.when(
      loading: () => _buildLoadingScreen(),
      error: (e, _) => _buildErrorScreen(e.toString()),
      data: (content) {
        if (content == null) return _buildErrorScreen('Content not found');
        return _buildDetailPage(content, isInWatchlist);
      },
    );
  }

  Widget _buildDetailPage(ContentDetail content, bool isInWatchlist) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomAppBar(
        showBackButton: true,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            // Hero section
            SliverToBoxAdapter(child: _HeroSection(content: content)),
            // Content body
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: Responsive(context).w(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo or Title
                    if (content.hasLogo)
                      _buildLogo(content.displayLogoUrl!)
                    else
                      Text(
                        content.title,
                        style: GoogleFonts.lora(
                          color: AppColors.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.8,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Meta Row
                    _buildMetaRow(content),
                    const SizedBox(height: 12),

                    // Genre Chips
                    if (content.genres != null && content.genres!.isNotEmpty)
                      _buildGenreChips(content.genres!),
                    const SizedBox(height: 20),

                    // Action Buttons
                    _buildActionButtons(content, isInWatchlist),

                    // Overview
                    if (content.overview != null &&
                        content.overview!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        content.overview!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.6,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    // Cast Section
                    if (content.castMembers.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildActorsSection(content.castMembers),
                    ],
                    // ─── Unified Tab Section (Episodes/Similars/Reviews/Share) ───
                    const SizedBox(height: 24),
                    _buildTabSection(content),

                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Hero Section Replaced by _HeroSection StatefulWidget ───────────────

  // ─── Logo ──────────────────────────────────────────────────────────────────
  Widget _buildLogo(String logoUrl) {
    final r = Responsive(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: r.w(220).clamp(160.0, 300.0),
        maxHeight: r.h(80).clamp(60.0, 100.0),
      ),
      child: CachedNetworkImage(
        imageUrl: logoUrl,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        placeholder: (_, __) => const SizedBox(height: 50),
        errorWidget: (_, __, ___) => Text(
          ref.read(detailProvider(_detailParams)).valueOrNull?.title ?? '',
          style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  // ─── Meta Row ──────────────────────────────────────────────────────────────
  Widget _buildMetaRow(ContentDetail content) {
    final items = <Widget>[];

    // Rating
    items.add(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 16, color: AppColors.ratingMid),
        const SizedBox(width: 3),
        Text(
          content.voteAverage.toStringAsFixed(1),
          style: GoogleFonts.inter(
              color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ));

    // Year
    if (content.releaseYear != null) {
      items.add(Text('${content.releaseYear}',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 14)));
    }

    // Runtime or Seasons
    if (content.isMovie && content.runtime != null && content.runtime! > 0) {
      final hours = content.runtime! ~/ 60;
      final mins = content.runtime! % 60;
      items.add(Text('${hours}h ${mins}m',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 14)));
    } else if (content.isTv && content.numberOfSeasons != null) {
      items.add(Text(
          '${content.numberOfSeasons} Season${content.numberOfSeasons! > 1 ? 's' : ''}',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 14)));
    }

    // IMDb link (uses real imdb_id)
    final imdbId = content.imdbId;
    if (imdbId != null && imdbId.isNotEmpty) {
      items.add(GestureDetector(
        onTap: () async {
          final url = 'https://www.imdb.com/title/$imdbId';
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new_rounded,
                size: 14,
                color: AppColors.textSecondary.withValues(alpha: 0.8)),
            const SizedBox(width: 3),
            Text('IMDb',
                style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 14)),
          ],
        ),
      ));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items.expand((e) sync* {
        if (e != items.first) {
          yield const Text('•',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14));
        }
        yield e;
      }).toList(),
    );
  }

  // ─── Genre Chips ───────────────────────────────────────────────────────────
  Widget _buildGenreChips(List<String> genres) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: genres
          .take(5)
          .map((g) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(g,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ))
          .toList(),
    );
  }

  // ─── Action Buttons ────────────────────────────────────────────────────────
  Widget _buildActionButtons(ContentDetail content, bool isInWatchlist) {
    String? watchLink;

    if (content.isMovie) {
      watchLink = content.primaryWatchLink;
    } else {
      // For TV: get first episode link from current season episodes
      final episodesAsync = ref.watch(episodesProvider(_getEpisodeParams(content)));
      final episodes = episodesAsync.valueOrNull ?? [];
      if (episodes.isNotEmpty) {
        watchLink = episodes.first.playLink;
      }
    }

    final bool hasWatch = watchLink != null && watchLink.isNotEmpty;
    return Row(
      children: [
        // Play Button
        GestureDetector(
          onTap: hasWatch
              ? () => _handlePlay(watchLink!,
                  season: content.isTv ? 1 : null,
                  episode: content.isTv ? 1 : null)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: hasWatch
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded,
                    color: Colors.white.withValues(alpha: hasWatch ? 1.0 : 0.6),
                    size: 24),
                const SizedBox(width: 6),
                Text('Play',
                    style: TextStyle(
                      color:
                          Colors.white.withValues(alpha: hasWatch ? 1.0 : 0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Watchlist Button
        _AnimatedActionButton(
          icon: isInWatchlist
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          onTap: () => _toggleWatchlist(content, isInWatchlist),
          isActive: isInWatchlist,
        ),
        const SizedBox(width: 12),

        // Download Button (movies only)
        if (content.isMovie)
          _AnimatedActionButton(
            icon: Icons.download_rounded,
            onTap: hasWatch ? () => _handleDownload(watchLink!) : null,
            isActive: false,
          ),
      ],
    );
  }

  // ─── Actors Section ────────────────────────────────────────────────────────
  Widget _buildActorsSection(List<CastMember> cast) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Actors',
            style: GoogleFonts.lora(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            itemBuilder: (context, index) {
              final actor = cast[index];
              final imageUrl = actor.profilePath != null
                  ? 'https://image.tmdb.org/t/p/w185${actor.profilePath}'
                  : null;

              return Padding(
                padding:
                    EdgeInsets.only(right: index < cast.length - 1 ? 16 : 0),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 1),
                      ),
                      child: ClipOval(
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
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
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 70,
                      child: Text(
                        actor.name,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Unified Tab Section ──────────────────────────────────────────────────
  Widget _buildTabSection(ContentDetail content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab selector
        Row(
          children: [
            if (content.isTv) ...[
              _buildTabChip('Episodes', 0),
              const SizedBox(width: 16),
            ],
            _buildTabChip('Similars', content.isTv ? 1 : 0),
            const SizedBox(width: 16),
            _buildTabChip('Reviews', content.isTv ? 2 : 1),
            const SizedBox(width: 16),
            _buildTabChip('Share', content.isTv ? 3 : 2),
          ],
        ),
        const SizedBox(height: 16),

        if (content.isTv && _tabIndex == 0)
          _buildEpisodesTab(content)
        else if ((content.isTv && _tabIndex == 1) || (!content.isTv && _tabIndex == 0))
          _buildSimilarsTab()
        else if ((content.isTv && _tabIndex == 2) || (!content.isTv && _tabIndex == 1))
          _buildReviewsTab()
        else if ((content.isTv && _tabIndex == 3) || (!content.isTv && _tabIndex == 2))
          _buildShareTab(content),
      ],
    );
  }

  Widget _buildTabChip(String label, int index) {
    final isSelected = _tabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _tabIndex = index);
        HapticFeedback.selectionClick();
      },
      child: Column(
        children: [
          Text(label,
              style: GoogleFonts.lora(
                color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              )),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: label.length * 8.0,
            color: isSelected ? AppColors.primary : Colors.transparent,
          ),
        ],
      ),
    );
  }



  // ─── Episodes Tab ─────────────────────────────────────────────────────────
  Widget _buildEpisodesTab(ContentDetail content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSeasonSearchRow(content),
        const SizedBox(height: 16),
        Consumer(builder: (context, ref, _) {
          final episodesAsync = ref.watch(episodesProvider(_getEpisodeParams(content)));
          return episodesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
              ),
            ),
            error: (e, _) => _buildEmptyTab(Icons.error_outline, 'Error loading episodes'),
            data: (episodes) {
              final filtered = _filterEpisodes(episodes);
              if (filtered.isEmpty) {
                return _buildEmptyTab(Icons.tv_off_rounded, 'No episodes available');
              }
              return Column(
                children: filtered.map((ep) => _buildEpisodeCard(ep, content)).toList(),
              );
            },
          );
        }),
      ],
    );
  }

  // ─── Similars Tab ─────────────────────────────────────────────────────────
  Widget _buildSimilarsTab() {
    final similarAsync = ref.watch(similarProvider(_detailParams));
    return similarAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
        ),
      ),
      error: (e, _) => _buildEmptyTab(Icons.error_outline, 'Failed to load similar content'),
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyTab(Icons.movie_filter_outlined, 'No similar content found');
        }
        return SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              return _buildSimilarCard(item);
            },
          ),
        );
      },
    );
  }

  Widget _buildSimilarCard(SimilarItem item) {
    final posterUrl =
        item.posterPath != null ? TmdbClient.posterUrl(item.posterPath) : null;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsScreen(tmdbId: item.id, mediaType: item.mediaType),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 110,
                  height: 160,
                  child: posterUrl != null && posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.movie, color: AppColors.textMuted),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(Icons.movie, color: AppColors.textMuted),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Reviews Tab ──────────────────────────────────────────────────────────
  Widget _buildReviewsTab() {
    final reviewsAsync = ref.watch(reviewsProvider(_detailParams));
    return reviewsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
        ),
      ),
      error: (e, _) => _buildEmptyTab(Icons.error_outline, 'Could not load reviews'),
      data: (reviews) {
        if (reviews.isEmpty) {
          return _buildEmptyTab(Icons.rate_review_outlined, 'No reviews yet');
        }
        return Column(
          children: reviews.map((review) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: Text(
                          review.author.isNotEmpty ? review.author[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              review.author,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            if (review.rating != null)
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: AppColors.ratingMid, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${review.rating!.toStringAsFixed(0)}/10',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ExpandableReviewContent(content: review.content),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ─── Share Tab ────────────────────────────────────────────────────────────
  Widget _buildShareTab(ContentDetail content) {
    final deepLink = 'https://daniewatch.app/${content.isTv ? 'tv' : 'movie'}/${content.id}';
    return Column(
      children: [
        _buildEmptyTab(Icons.share_rounded, 'Share with friends'),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildShareAction(Icons.copy_rounded, 'Copy Link', () {
                Clipboard.setData(ClipboardData(text: deepLink));
                CustomToast.show(context, 'Link copied!', type: ToastType.success, icon: Icons.check_rounded);
              }),
              const SizedBox(width: 48),
              _buildShareAction(Icons.send_rounded, 'Share', () {
                Share.share('Check out ${content.title} on DanieWatch!\n\n$deepLink');
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShareAction(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }

  // ─── Empty State Helper ───────────────────────────────────────────────────
  Widget _buildEmptyTab(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.6), fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildSeasonSearchRow(ContentDetail content) {
    final seasonNums = content.seasonNumbers;
    final tmdbSeasons = content.tmdbSeasons;

    return Row(
      children: [
        // Season dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: seasonNums.contains(_selectedSeason)
                  ? _selectedSeason
                  : seasonNums.first,
              dropdownColor: AppColors.surfaceElevated,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary, size: 20),
              items: seasonNums.map((seasonNum) {
                String label = 'Season $seasonNum';
                if (tmdbSeasons != null) {
                  final match = tmdbSeasons
                      .where((s) => s.seasonNumber == seasonNum)
                      .firstOrNull;
                  if (match?.name != null &&
                      match!.name!.isNotEmpty &&
                      match.name != 'Season $seasonNum') {
                    label = match.name!;
                  }
                }
                return DropdownMenuItem(value: seasonNum, child: Text(label));
              }).toList(),
              onChanged: (v) {
                if (v != null && v != _selectedSeason) {
                  setState(() => _selectedSeason = v);
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Search field
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Material(
              color: Colors.transparent,
              child: TextField(
                onChanged: (v) => setState(() => _episodeSearch = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.6),
                      fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textMuted, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<EpisodeData> _filterEpisodes(List<EpisodeData> episodes) {
    if (_episodeSearch.isEmpty) return episodes;
    final q = _episodeSearch.toLowerCase();
    return episodes.where((ep) {
      final title = ep.title?.toLowerCase() ?? '';
      final desc = ep.description?.toLowerCase() ?? '';
      return title.contains(q) || desc.contains(q);
    }).toList();
  }

  Widget _buildEpisodeCard(EpisodeData episode, ContentDetail content) {
    final hasPlayLink =
        episode.playLink != null && episode.playLink!.isNotEmpty;
    final epNum = episode.episodeNumber ?? 0;

    return GestureDetector(
      onTap: hasPlayLink
          ? () => _handlePlay(episode.playLink!,
              season: _selectedSeason, episode: epNum)
          : () =>
              _showToastError('No play link available for ${episode.title}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thumbnail with episode number
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 140,
                    height: 85,
                    child: episode.thumbnailUrl != null &&
                            episode.thumbnailUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: episode.thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: AppColors.surfaceElevated),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.play_circle_outline,
                                  color: AppColors.textMuted),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.play_circle_fill,
                                color: AppColors.textMuted, size: 32),
                          ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('E$epNum',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),

            // Episode info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    episode.title ?? 'Episode $epNum',
                    style: TextStyle(
                      color: hasPlayLink ? Colors.white : AppColors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (episode.runtime != null) ...[
                    const SizedBox(height: 6),
                    Text('${episode.runtime}m',
                        style: TextStyle(
                            color: AppColors.textMuted.withValues(alpha: 0.6),
                            fontSize: 12)),
                  ],
                ],
              ),
            ),

            // Vertical Divider
            Container(
              height: 40,
              width: 1,
              color: Colors.white10,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),

            // Download button (Icon Only) — uses playLink as download source
            GestureDetector(
              onTap: hasPlayLink
                  ? () => _startDownload(episode.playLink!, epNum, content)
                  : () => _showToastError('No play/download link available'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasPlayLink
                      ? AppColors.surfaceElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: hasPlayLink
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 1),
                ),
                child: Icon(
                  Icons.download_rounded,
                  color: hasPlayLink
                      ? AppColors.primary
                      : AppColors.textMuted.withValues(alpha: 0.3),
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  void _toggleWatchlist(ContentDetail content, bool currentIsInWatchlist) {
    HapticFeedback.lightImpact();

    // Optmistically update through the provider
    ref.read(watchlistProvider.notifier).toggle(
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          title: content.title,
          posterPath: content.posterUrl,
          voteAverage: content.voteAverage,
        );

    if (mounted) {
      CustomToast.show(
        context,
        currentIsInWatchlist ? 'Removed from watchlist' : 'Added to watchlist',
        type: currentIsInWatchlist ? ToastType.info : ToastType.success,
        icon: currentIsInWatchlist
            ? Icons.bookmark_remove_rounded
            : Icons.bookmark_added_rounded,
      );
    }
  }

  // ─── Download Logic ────────────────────────────────────────────────────────
  void _startDownload(
      String url, int episodeNumber, ContentDetail content) async {
    HapticFeedback.mediumImpact();

    if (!mounted) return;

    // 1. Immediately morph navbar to loading modal
    final selectionFuture = showQualitySelectorSheet(
      context: context,
      ref: ref,
      m3u8Url: '', // To be updated
      title: content.title,
      isLoading: true,
      season: content.isMovie ? null : _selectedSeason,
      episode: content.isMovie ? null : episodeNumber,
      isMovie: content.isMovie,
      fallbackQuality: content.result,
      fallbackLanguage: content.language,
    );

    String? m3u8Url;
    try {
      // 2. Extract m3u8 URL in the background
      final extractor = VideoExtractorService();
      m3u8Url = await extractor.extractVideoUrl(url, bypassCache: true);

      // Auto-Recovery: if first attempt fails, retry once
      if ((m3u8Url == null || m3u8Url.isEmpty) && mounted) {
        debugPrint('[Download] First extraction failed, retrying...');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('extract_$url');
        m3u8Url = await extractor.extractVideoUrl(url, bypassCache: true);
      }

      if (!mounted) return;

      if (m3u8Url == null || m3u8Url.isEmpty) {
        // Close modal and show error
        ref.read(downloadModalProvider.notifier).state =
            const DownloadModalState();
        _showToastError('Could not find stream source.');
        return;
      }

      // 3. Update modal with the real URL and stop loading skeleton
      ref.read(downloadModalProvider.notifier).update((state) => state.copyWith(
            m3u8Url: m3u8Url,
            isLoading: false,
          ));
    } catch (e) {
      if (mounted) {
        ref.read(downloadModalProvider.notifier).state =
            const DownloadModalState();
        _showToastError('Extraction error. Please try again.');
      }
      return;
    }

    // 4. Wait for user to pick quality/audio
    final selection = await selectionFuture;
    if (selection == null || !mounted) return;

    // 5. Start ffmpeg download (with a tiny delay to ensure sheet closes smoothly if needed,
    // although our provider handles the closing animation via morphing back)
    try {
      // Ensure we don't block the UI thread during initialization
      final item = await DownloadManager.instance.startSegmentDownload(
        m3u8Url: m3u8Url,
        title: content.title,
        season: _selectedSeason,
        episode: episodeNumber,
        posterUrl: content.posterUrl,
        variant: selection.quality,
        audioTrack: selection.audioTrack,
        subtitleTrack: selection.subtitleTrack,
      );
      if (item != null && mounted) {
        _showDownloadStartedToast(item);
      }
    } catch (e) {
      if (mounted) {
        _showToastError('Failed to start download: $e');
      }
    }
  }

  void _showDownloadStartedToast(DownloadItem item) {
    if (!mounted) return;

    CustomToast.show(
      context,
      'Download started',
      type: ToastType.info,
      icon: Icons.download_done_rounded,
    );
  }

  // ─── Playback ──────────────────────────────────────────────────────────────
  Future<void> _handlePlay(String url, {int? season, int? episode}) async {
    HapticFeedback.lightImpact();

    if (url.isEmpty) {
      _showToastError('Invalid video link');
      return;
    }

    final content = ref.read(detailProvider(_detailParams)).valueOrNull;

    // Show Loader and start background extraction
    showPlayLoader(
      context: context,
      fetchLinkFuture: () async {
        try {
          final extractor = VideoExtractorService();
          String? m3u8Url =
              await extractor.extractVideoUrl(url, bypassCache: true);

          // Auto-Recovery: if first attempt fails, retry once
          if (m3u8Url == null || m3u8Url.isEmpty) {
            debugPrint('[PlayLoader] First extraction failed, retrying...');
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('extract_$url');
            m3u8Url = await extractor.extractVideoUrl(url, bypassCache: true);
          }
          return m3u8Url;
        } catch (e) {
          debugPrint('[PlayLoader] Extraction error: $e');
          return null; // Will trigger 'Try Again' downstream
        }
      },
      onSuccess: (extractedLink) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacement(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => VideoPlayerScreen(
              url: extractedLink,
              title: content?.title ?? '',
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              seasons: content?.seasonNumbers,
              season: season,
              episode: episode,
              isDirectLink: true,
            ),
          ),
        );
      },
      onError: () {
        _showToastError('Try Again');
      },
    );
  }

  Future<void> _handleDownload(String url) async {
    HapticFeedback.mediumImpact();
    if (url.isEmpty) {
      _showToastError('Invalid download link');
      return;
    }

    final content = ref.read(detailProvider(_detailParams)).valueOrNull;
    if (content != null) {
      // episode 0 signifies it's a movie, use watch link
      _startDownload(url, 0, content);
    }
  }

  void _showToastError(String message) {
    if (mounted) {
      CustomToast.show(
        context,
        message,
        type: ToastType.error,
      );
    }
  }

  // ─── Error Screen ──────────────────────────────────────────────────────────
  Widget _buildErrorScreen(String message) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.textMuted, size: 64),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(detailProvider(_detailParams)),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Loading Skeleton ──────────────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Shimmer.fromColors(
        baseColor: AppColors.surface,
        highlightColor: AppColors.surfaceElevated,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 360, color: Colors.white),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 30,
                        width: 200,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 12),
                    Container(
                        height: 16,
                        width: 250,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                          height: 48,
                          width: 120,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24))),
                      const SizedBox(width: 12),
                      Container(
                          height: 48,
                          width: 48,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 12),
                      Container(
                          height: 48,
                          width: 48,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 24),
                    Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(
                        height: 14,
                        width: 280,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 24),
                    Container(
                        height: 20,
                        width: 80,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 5,
                        itemBuilder: (_, __) => Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Column(children: [
                            Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle)),
                          ]),
                        ),
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

/// Animated action button with scale bounce and color transition
class _AnimatedActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;

  const _AnimatedActionButton({
    required this.icon,
    this.onTap,
    this.isActive = false,
  });

  @override
  State<_AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<_AnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.25), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.95), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    _controller.forward(from: 0);
    HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isActive
                  ? AppColors.primary
                  : AppColors.textMuted.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              widget.icon,
              key: ValueKey(widget.icon),
              color:
                  widget.isActive ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
class _ExpandableReviewContent extends StatefulWidget {
  final String content;

  const _ExpandableReviewContent({required this.content});

  @override
  State<_ExpandableReviewContent> createState() => _ExpandableReviewContentState();
}

class _ExpandableReviewContentState extends State<_ExpandableReviewContent> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.content,
          maxLines: _isExpanded ? null : 4,
          overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if (widget.content.length > 200)
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isExpanded ? 'Show Less' : 'Read More',
                style: const TextStyle(
                  color: AppColors.primary,
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

// ─── Hero Section (with Autoplay Trailer via InAppWebView) ───────────────────
class _HeroSection extends StatefulWidget {
  final ContentDetail content;

  const _HeroSection({required this.content});

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  InAppWebViewController? _webViewController;
  bool _isMuted = true;
  bool _hasTrailer = false;
  bool _trailerReady = false;

  String? _videoId;

  @override
  void initState() {
    super.initState();
    _extractVideoId();
  }

  @override
  void didUpdateWidget(covariant _HeroSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.trailerUrl != widget.content.trailerUrl) {
      _extractVideoId();
    }
  }

  void _extractVideoId() {
    final url = widget.content.trailerUrl;
    if (url != null && url.isNotEmpty) {
      // Extract video ID from various YouTube URL formats
      final uri = Uri.tryParse(url);
      String? id;
      if (uri != null) {
        if (uri.host.contains('youtu.be')) {
          id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        } else if (uri.queryParameters.containsKey('v')) {
          id = uri.queryParameters['v'];
        } else if (uri.pathSegments.contains('embed') && uri.pathSegments.length > 1) {
          id = uri.pathSegments[uri.pathSegments.indexOf('embed') + 1];
        }
      }
      // Fallback regex
      if (id == null || id.isEmpty) {
        final regex = RegExp(r'(?:v=|\/embed\/|youtu\.be\/)([a-zA-Z0-9_-]{11})');
        final match = regex.firstMatch(url);
        id = match?.group(1);
      }
      setState(() {
        _videoId = id;
        _hasTrailer = id != null && id.isNotEmpty;
        _trailerReady = false;
      });
    } else {
      setState(() {
        _videoId = null;
        _hasTrailer = false;
        _trailerReady = false;
      });
    }
  }

  // JavaScript to inject after YouTube page loads — hides all chrome,
  // forces the video player to fill viewport, and auto-plays muted.
  static const String _hideYouTubeChromeJs = r'''
    (function() {
      var style = document.createElement('style');
      style.textContent = `
        /* Hide all YouTube chrome */
        ytm-mobile-topbar-renderer,
        ytm-pivot-bar-renderer,
        .player-controls-top,
        .player-controls-bottom,
        ytm-item-section-renderer,
        ytm-comments-entry-point-header-renderer,
        ytm-engagement-panel-section-list-renderer,
        ytm-related-chip-cloud-renderer,
        ytm-compact-video-renderer,
        ytm-compact-autoplay-renderer,
        .slim-video-information-renderer,
        .slim-owner-renderer,
        .menu-renderer,
        ytm-section-list-renderer,
        .single-column-watch-next-results,
        #secondary, #below, #related, #comments, #chat,
        .ytp-chrome-top, .ytp-chrome-bottom,
        .ytp-gradient-top, .ytp-gradient-bottom,
        .ytp-pause-overlay, .ytp-watermark,
        .ytp-show-cards-title, .ytp-ce-element,
        .ytp-endscreen-content, .branding-img-container,
        ytm-watch-metadata-app-promo-renderer,
        .player-controls-middle, #player-control-overlay,
        .ytp-overflow-menu-button, .ytp-settings-button,
        .related-chips-slot-wrapper, .watch-below-the-player,
        ytm-single-column-watch-next-results-renderer > *:not(.player-container) {
          display: none !important;
          visibility: hidden !important;
          height: 0 !important;
          overflow: hidden !important;
        }
        html, body {
          margin: 0 !important; padding: 0 !important;
          overflow: hidden !important; background: #141413 !important;
        }
        .player-container, #player, #movie_player,
        .html5-video-container {
          position: fixed !important;
          top: 0 !important; left: 0 !important;
          width: 100vw !important; height: 100vh !important;
          max-height: 100vh !important; min-height: 100vh !important;
          z-index: 99999 !important; object-fit: cover !important;
          background: #141413 !important;
        }
        video {
          position: fixed !important;
          top: 50% !important; left: 50% !important;
          min-width: 100vw !important; min-height: 100vh !important;
          width: auto !important; height: auto !important;
          z-index: 99999 !important; object-fit: cover !important;
          transform: translate(-50%, -50%) scale(1.5) !important;
          background: #141413 !important;
        }
        ytm-app, ytm-watch { overflow: hidden !important; }
      `;
      document.head.appendChild(style);

      function tryAutoplay() {
        var video = document.querySelector('video');
        if (video) {
          video.muted = true;
          video.loop = true;
          video.setAttribute('playsinline', '');
          video.play().catch(function(){});
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onTrailerReady');
          }
          return true;
        }
        return false;
      }

      if (!tryAutoplay()) {
        var attempts = 0;
        var interval = setInterval(function() {
          attempts++;
          if (tryAutoplay() || attempts > 30) clearInterval(interval);
        }, 500);
      }

      var observer = new MutationObserver(function() {
        var video = document.querySelector('video');
        if (video) {
          video.muted = true; video.loop = true;
          video.play().catch(function(){});
          observer.disconnect();
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    })();
  ''';

  void _toggleMute() {
    if (_webViewController == null || !_hasTrailer) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    _webViewController!.evaluateJavascript(source: '''
      var video = document.querySelector('video');
      if (video) { video.muted = ${_isMuted}; }
    ''');
  }

  @override
  void dispose() {
    _webViewController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final heroHeight = r.h(420).clamp(320.0, 520.0);

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: Trailer or Backdrop ──
          if (_hasTrailer && _videoId != null)
            Stack(
              fit: StackFit.expand,
              children: [
                // Show backdrop behind while loading
                if (widget.content.backdropUrl != null && widget.content.backdropUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: widget.content.backdropUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _buildFallbackBackdrop(),
                  ),
                // WebView trailer layer — fills entire hero area like the backdrop
                Positioned.fill(
                  child: AbsorbPointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 600),
                      opacity: _trailerReady ? 1.0 : 0.0,
                      child: ClipRect(
                        child: InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri('https://m.youtube.com/watch?v=$_videoId'),
                          ),
                          initialSettings: InAppWebViewSettings(
                            mediaPlaybackRequiresUserGesture: false,
                            allowsInlineMediaPlayback: true,
                            transparentBackground: true,
                            javaScriptEnabled: true,
                            useHybridComposition: true,
                            disableVerticalScroll: true,
                            disableHorizontalScroll: true,
                            supportZoom: false,
                            builtInZoomControls: false,
                            displayZoomControls: false,
                            verticalScrollBarEnabled: false,
                            horizontalScrollBarEnabled: false,
                            userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                          ),
                          onWebViewCreated: (controller) {
                            _webViewController = controller;
                            controller.addJavaScriptHandler(
                              handlerName: 'onTrailerReady',
                              callback: (args) {
                                Future.delayed(const Duration(milliseconds: 800), () {
                                  if (mounted) {
                                    setState(() => _trailerReady = true);
                                  }
                                });
                              },
                            );
                          },
                          onLoadStop: (controller, url) async {
                            await controller.evaluateJavascript(source: _hideYouTubeChromeJs);
                            Future.delayed(const Duration(milliseconds: 2000), () {
                              if (mounted) controller.evaluateJavascript(source: _hideYouTubeChromeJs);
                            });
                            Future.delayed(const Duration(milliseconds: 4000), () {
                              if (mounted) controller.evaluateJavascript(source: _hideYouTubeChromeJs);
                            });
                          },
                          shouldOverrideUrlLoading: (controller, navigationAction) async {
                            final navUrl = navigationAction.request.url?.toString() ?? '';
                            if (navUrl.contains('youtube.com') ||
                                navUrl.contains('consent.google') ||
                                navUrl.contains('accounts.google')) {
                              return NavigationActionPolicy.ALLOW;
                            }
                            return NavigationActionPolicy.CANCEL;
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else if (widget.content.backdropUrl != null && widget.content.backdropUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: widget.content.backdropUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _buildFallbackBackdrop(),
            )
          else
            _buildFallbackBackdrop(),

          // ── Vignette Gradient Overlay (same for both trailer and backdrop) ──
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.25),
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.background.withValues(alpha: 0.5),
                      AppColors.background.withValues(alpha: 0.85),
                      AppColors.background,
                    ],
                    stops: const [0.0, 0.15, 0.4, 0.7, 0.88, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Back Button (top-left) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),

          // ── Mute/Unmute Button (top-right) ──
          if (_hasTrailer && _trailerReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackBackdrop() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Icon(Icons.movie_outlined, color: AppColors.textMuted.withValues(alpha: 0.3), size: 80),
      ),
    );
  }
}

