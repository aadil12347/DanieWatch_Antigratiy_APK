import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../providers/download_modal_provider.dart';
import '../../widgets/custom_toast.dart';
import '../../widgets/quality_selector_sheet.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/clients/tmdb_client.dart';
import '../../../data/local/download_manager.dart';
import '../../../domain/models/content_detail.dart';
import '../../../domain/models/entry.dart';
import '../../../services/video_extractor_service.dart';
import '../../providers/detail_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../widgets/custom_app_bar.dart';
import '../video_player/video_player_screen.dart';
import '../downloads/downloads_screen.dart';

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
  int _tabIndex = 0; // 0 = Episodes, 1 = Similars
  String _episodeSearch = '';

  DetailParams get _detailParams =>
      DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType);

  EpisodeParams get _episodeParams =>
      EpisodeParams(tmdbId: widget.tmdbId, seasonNumber: _selectedSeason);

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(detailProvider(_detailParams));

    return detailAsync.when(
      loading: () => _buildLoadingScreen(),
      error: (e, _) => _buildErrorScreen(e.toString()),
      data: (content) {
        if (content == null) return _buildErrorScreen('Content not found');
        return _buildDetailPage(content);
      },
    );
  }

  Widget _buildDetailPage(ContentDetail content) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomAppBar(
        showBackButton: true,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Hero section
            SliverToBoxAdapter(child: _buildHeroSection(content)),
            // Content body
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo or Title
                    if (content.hasLogo)
                      _buildLogo(content.displayLogoUrl!)
                    else
                      Text(
                        content.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
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
                    _buildActionButtons(content),

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

                    // TV Episodes / Similars Section
                    if (content.isTv) ...[
                      const SizedBox(height: 24),
                      _buildTvSection(content),
                    ],

                    // Movie Similars
                    if (content.isMovie) ...[
                      const SizedBox(height: 24),
                      _buildSimilarsSection(),
                    ],

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

  // ─── Hero Section ──────────────────────────────────────────────────────────
  Widget _buildHeroSection(ContentDetail content) {
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (content.backdropUrl != null && content.backdropUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: content.backdropUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _buildFallbackBackdrop(),
            )
          else if (content.posterUrl != null && content.posterUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: content.posterUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _buildFallbackBackdrop(),
            )
          else
            _buildFallbackBackdrop(),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  AppColors.background.withValues(alpha: 0.5),
                  AppColors.background.withValues(alpha: 0.9),
                  AppColors.background,
                ],
                stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
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
        child: Icon(Icons.movie_outlined,
            color: AppColors.textMuted.withValues(alpha: 0.3), size: 80),
      ),
    );
  }

  // ─── Logo ──────────────────────────────────────────────────────────────────
  Widget _buildLogo(String logoUrl) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 80),
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
        const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
        const SizedBox(width: 3),
        Text(
          content.voteAverage.toStringAsFixed(1),
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
  Widget _buildActionButtons(ContentDetail content) {
    String? watchLink;
    String? downloadLink;

    if (content.isMovie) {
      watchLink = content.watchLink ?? content.playUrl;
      downloadLink = content.downloadLink ?? content.downloadUrl;
    } else {
      // For TV: get first episode link from current season episodes
      final episodesAsync = ref.watch(episodesProvider(_episodeParams));
      final episodes = episodesAsync.valueOrNull ?? [];
      if (episodes.isNotEmpty) {
        watchLink = episodes.first.playLink;
        downloadLink = episodes.first.downloadLink;
      }
    }

    final bool hasWatch = watchLink != null && watchLink.isNotEmpty;
    // User wants to use watchLink for download as well
    final bool hasDownload = hasWatch; 

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
          icon: _isInWatchlist()
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          onTap: () => _toggleWatchlist(content),
          isActive: _isInWatchlist(),
        ),
        const SizedBox(width: 12),

        // Download Button (movies only)
        if (content.isMovie)
          _AnimatedActionButton(
            icon: Icons.download_rounded,
            onTap: hasDownload ? () => _handleDownload(watchLink!) : null,
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
        const Text('Actors',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
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

  // ─── TV Section ────────────────────────────────────────────────────────────
  Widget _buildTvSection(ContentDetail content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab selector
        Row(
          children: [
            _buildTabButton('Episodes', 0),
            const SizedBox(width: 16),
            _buildTabButton('Similars', 1),
          ],
        ),
        const SizedBox(height: 16),

        if (_tabIndex == 0) ...[
          _buildSeasonSearchRow(content),
          const SizedBox(height: 16),

          // Episodes from provider
          Consumer(builder: (context, ref, _) {
            final episodesAsync = ref.watch(episodesProvider(_episodeParams));
            return episodesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2),
                ),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('Error loading episodes',
                        style: TextStyle(color: AppColors.textMuted))),
              ),
              data: (episodes) {
                final filtered = _filterEpisodes(episodes);
                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No episodes available',
                            style: TextStyle(color: AppColors.textMuted))),
                  );
                }
                return Column(
                    children: filtered
                        .map((ep) => _buildEpisodeCard(ep, content))
                        .toList());
              },
            );
          }),
        ] else ...[
          _buildSimilarsSection(),
        ],
      ],
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textMuted,
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
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

  Widget _buildSeasonSearchRow(ContentDetail content) {
    final seasonNums = content.seasonNumbers;
    final tmdbSeasons = content.tmdbSeasons;

    return Row(
      children: [
        // Season dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
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
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
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
    final hasDownloadLink =
        episode.downloadLink != null && episode.downloadLink!.isNotEmpty;
    final epNum = episode.episodeNumber ?? 0;

    return GestureDetector(
      onTap: hasPlayLink
          ? () => _handlePlay(episode.playLink!,
              season: _selectedSeason, episode: epNum)
          : () =>
              _showErrorSnackBar('No play link available for ${episode.title}'),
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

            // Download button (Icon Only)
            GestureDetector(
              onTap: hasPlayLink
                  ? () => _startDownload(episode.playLink!, epNum, content)
                  : () => _showErrorSnackBar('No play/download link available'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasDownloadLink
                      ? AppColors.surfaceElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: hasDownloadLink
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 1),
                ),
                child: Icon(
                  Icons.download_rounded,
                  color: hasDownloadLink
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

  // ─── Similars Section ──────────────────────────────────────────────────────
  Widget _buildSimilarsSection() {
    final similarAsync = ref.watch(similarProvider(_detailParams));

    return similarAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text('No similar content found',
                    style: TextStyle(color: AppColors.textMuted))),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ref.read(detailProvider(_detailParams)).valueOrNull?.isMovie ??
                false) ...[
              const Text('Similar',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _buildSimilarCard(item);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSimilarCard(SimilarItem item) {
    final posterUrl =
        item.posterPath != null ? TmdbClient.posterUrl(item.posterPath) : null;

    return GestureDetector(
      onTap: () {
        // Navigate to similar content detail
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DetailsScreen(tmdbId: item.id, mediaType: item.mediaType),
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
                          placeholder: (_, __) =>
                              Container(color: AppColors.surfaceElevated),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.movie,
                                color: AppColors.textMuted),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(Icons.movie,
                              color: AppColors.textMuted),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Watchlist Logic ───────────────────────────────────────────────────────
  bool _isInWatchlist() {
    final notifier = ref.read(watchlistProvider.notifier);
    return notifier.isInWatchlist(widget.tmdbId, widget.mediaType);
  }

  void _toggleWatchlist(ContentDetail content) {
    HapticFeedback.lightImpact();
    final wasInWatchlist = _isInWatchlist();
    ref.read(watchlistProvider.notifier).toggle(
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          title: content.title,
          posterPath: content.posterUrl,
          voteAverage: content.voteAverage,
        );
    setState(() {});
    if (mounted) {
      CustomToast.show(
        context,
        message:
            wasInWatchlist ? 'Removed from watchlist' : 'Added to watchlist',
        type: wasInWatchlist ? ToastType.info : ToastType.success,
        icon: wasInWatchlist
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
      season: _selectedSeason,
      episode: episodeNumber,
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
        ref.read(downloadModalProvider.notifier).state = DownloadModalState();
        _showErrorSnackBar('Could not find stream source.');
        return;
      }

      // 3. Update modal with the real URL and stop loading skeleton
      ref.read(downloadModalProvider.notifier).update((state) => state.copyWith(
            m3u8Url: m3u8Url,
            isLoading: false,
          ));
    } catch (e) {
      if (mounted) {
        ref.read(downloadModalProvider.notifier).state = DownloadModalState();
        _showErrorSnackBar('Extraction error. Please try again.');
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
        m3u8Url: m3u8Url!,
        title: content.title,
        season: _selectedSeason,
        episode: episodeNumber,
        posterUrl: content.posterUrl,
        variant: selection.quality,
        audioTrack: selection.audioTrack,
      );
      if (item != null && mounted) {
        _showDownloadStartedToast(item);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to start download: $e');
      }
    }
  }

  void _showDownloadStartedToast(DownloadItem item) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.download_done_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${item.qualityTag.isNotEmpty ? "${item.qualityTag} · " : ""}Download started',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () => context.push('/downloads'),
        ),
      ),
    );
  }

  // ─── Playback ──────────────────────────────────────────────────────────────
  Future<void> _handlePlay(String url, {int? season, int? episode}) async {
    HapticFeedback.lightImpact();

    if (url.isEmpty) {
      _showErrorSnackBar('Invalid video link');
      return;
    }

    if (mounted) {
    final content = ref.read(detailProvider(_detailParams)).valueOrNull;
    
    if (mounted) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            url: url,
            title: content?.title ?? '',
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            seasons: content?.seasonNumbers,
            season: season,
            episode: episode,
          ),
        ),
      );
    }
    }
  }

  Future<void> _handleDownload(String url) async {
    HapticFeedback.mediumImpact();
    if (url.isEmpty) {
      _showErrorSnackBar('Invalid download link');
      return;
    }

    final content = ref.read(detailProvider(_detailParams)).valueOrNull;
    if (content != null) {
      // episode 0 signifies it's a movie, use watch link
      _startDownload(url, 0, content);
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      CustomToast.show(
        context,
        message: message,
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
