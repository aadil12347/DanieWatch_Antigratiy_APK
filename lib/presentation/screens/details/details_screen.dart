import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';


import '../../providers/download_modal_provider.dart';
import '../../providers/actor_modal_provider.dart';
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
import '../../../services/peachify_extractor.dart';
import '../../../services/vcloud_extractor.dart';
import '../../../core/services/deep_link_service.dart';
import '../../providers/detail_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/sticky_dropdown_modal.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/liquid_tap_effect.dart';

import '../video_player/video_player_screen.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/batch_zip_modal_provider.dart';
import '../../../services/extraction/site_post_extractor.dart';
import '../../../services/extraction/movie_site_scraper_service.dart';
import '../../../services/extraction/series_vcloud_repository.dart';

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
  bool _crawlerInitiated = false;

  void _triggerSeriesCrawl(ContentDetail content) {
    if (_crawlerInitiated || !content.isTv) return;
    _crawlerInitiated = true;
    final postUrl = content.postUrl ??
        MovieSiteScraperService.instance.getPostUrl(content.id) ??
        MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
        '';
    if (postUrl.isNotEmpty) {
      SeriesVcloudRepository.instance.crawlAllSeasonsVcloud(
        postUrl: postUrl,
        prioritySeason: _selectedSeason,
        posterUrl: content.posterUrl,
      );
    } else {
      SitePostExtractor.instance.findPostUrl(
        title: content.title,
        tmdbId: widget.tmdbId,
        year: content.releaseYear,
        imdbId: content.imdbId,
      ).then((pUrl) {
        if (pUrl != null && pUrl.isNotEmpty) {
          SeriesVcloudRepository.instance.crawlAllSeasonsVcloud(
            postUrl: pUrl,
            prioritySeason: _selectedSeason,
            posterUrl: content.posterUrl,
          );
        }
      });
    }
  }

  DetailParams get _detailParams =>
      DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType);

  EpisodeParams _getEpisodeParams(ContentDetail? content, {List<int>? availableEpisodeNumbers}) =>
      EpisodeParams(
        tmdbId: widget.tmdbId,
        seasonNumber: _selectedSeason,
        seasonsData: content?.seasonsData,
        isAdmin: content?.isAdmin ?? false,
        availableEpisodeNumbers: availableEpisodeNumbers,
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
    _triggerSeriesCrawl(content);
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomAppBar(
        showBackButton: true,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            // Hero and Content body combined in a Stack to enforce Z-ordering over the WebView
            SliverToBoxAdapter(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _HeroSection(content: content),
                  Container(
                    margin: EdgeInsets.only(top: Responsive(context).h(420).clamp(320.0, 520.0) - 40.0),
                    padding: EdgeInsets.symmetric(horizontal: Responsive(context).w(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Logo or Title
                    if (content.hasLogo)
                      _buildLogo(content.displayLogoUrl!)
                    else
                      Text(
                        content.cleanTitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
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
                ],
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
    final bool hasWatch = true;
    return Row(
      children: [
        LiquidTapEffect(
          onTap: hasWatch
              ? () => _handlePlay(
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
        if (content.isMovie) ...[
          StreamBuilder<DownloadItem>(
            stream: DownloadManager.instance.updateStream,
            builder: (context, _) {
              final match = DownloadManager.instance.downloads.cast<DownloadItem?>().firstWhere(
                (d) => d!.title == content.title && d.season == 0 && d.episode == 0,
                orElse: () => null,
              );
              final isPaused = match != null && match.status == DownloadStatus.paused;
              final isActiveDownload = match != null &&
                  (match.status == DownloadStatus.downloading ||
                   match.status == DownloadStatus.pending ||
                   match.status == DownloadStatus.converting ||
                   match.status == DownloadStatus.paused);
              final isCompleted = match != null && match.status == DownloadStatus.completed;
              final progress = match?.progress ?? 0.0;

              if (isCompleted) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    CustomToast.show(context, 'Already Downloaded', type: ToastType.success);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                  ),
                );
              }

              if (isActiveDownload) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (match!.is10Gbps) {
                      CustomToast.show(context, 'Pause/resume not supported for this link', type: ToastType.warning);
                      return;
                    }
                    if (isPaused) {
                      DownloadManager.instance.resumeDownload(match.id);
                    } else if (match.status == DownloadStatus.downloading) {
                      DownloadManager.instance.pauseDownload(match.id);
                    }
                  },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(
                            value: (match?.status == DownloadStatus.pending) ? null : progress,
                            strokeWidth: 2.5,
                            color: isPaused ? Colors.orangeAccent : AppColors.primary,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        Icon(
                          match?.is10Gbps == true
                              ? Icons.arrow_downward_rounded
                              : (isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          color: (isPaused ? Colors.orangeAccent : AppColors.primary).withValues(alpha: 0.7),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return _AnimatedActionButton(
                icon: Icons.download_rounded,
                onTap: hasWatch ? () => _startDownload(0, content) : null,
                isActive: false,
              );
            },
          ),
          const SizedBox(width: 12),
        ],

        // Download Button for TV Series (Batch/Zip options)
        if (content.isTv) ...[
          StreamBuilder<DownloadItem>(
            stream: DownloadManager.instance.updateStream,
            builder: (context, _) {
              final match = DownloadManager.instance.downloads.where(
                (d) => d.tmdbId == widget.tmdbId && d.season == _selectedSeason && d.fileExtension == 'zip',
              ).firstOrNull;
              final isPaused = match != null && match.status == DownloadStatus.paused;
              final isActiveDownload = match != null &&
                  (match.status == DownloadStatus.downloading ||
                   match.status == DownloadStatus.pending ||
                   match.status == DownloadStatus.converting ||
                   match.status == DownloadStatus.paused);
              final isCompleted = match != null && match.status == DownloadStatus.completed;
              final progress = match?.progress ?? 0.0;

              if (isCompleted) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    CustomToast.show(context, 'Season $_selectedSeason Batch Zip Downloaded', type: ToastType.success);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                  ),
                );
              }

              if (isActiveDownload) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (match.is10Gbps) {
                      CustomToast.show(context, 'Pause/resume not supported for this link', type: ToastType.warning);
                      return;
                    }
                    if (isPaused) {
                      DownloadManager.instance.resumeDownload(match.id);
                    } else if (match.status == DownloadStatus.downloading) {
                      DownloadManager.instance.pauseDownload(match.id);
                    }
                  },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(
                            value: (match.status == DownloadStatus.pending) ? null : progress,
                            strokeWidth: 2.5,
                            color: isPaused ? Colors.orangeAccent : AppColors.primary,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        Icon(
                          match.is10Gbps
                              ? Icons.arrow_downward_rounded
                              : (isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          color: (isPaused ? Colors.orangeAccent : AppColors.primary).withValues(alpha: 0.7),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return _AnimatedActionButton(
                icon: Icons.download_rounded,
                onTap: () {
                  final postUrl = MovieSiteScraperService.instance.getPostUrl(widget.tmdbId);
                  ref.read(batchZipModalProvider.notifier).state = BatchZipModalState(
                    isOpen: true,
                    content: content,
                    seasonNumber: _selectedSeason,
                    postUrl: postUrl,
                  );
                },
                isActive: false,
              );
            },
          ),
          const SizedBox(width: 12),
        ],

        // Share Button
        _AnimatedActionButton(
          icon: Icons.share_rounded,
          onTap: () => _handleQuickShare(content),
          isActive: false,
        ),
      ],
    );
  }

  /// Quick share via the action button — opens the system share sheet directly.
  void _handleQuickShare(ContentDetail content) {
    HapticFeedback.lightImpact();
    final mediaType = content.isTv ? 'tv' : 'movie';
    final shareLink = DeepLinkService.buildShareLink(mediaType, content.id);
    final year = _getShareYear(content);
    final typeLabel = content.isTv ? 'Season' : 'Movie';
    final yearSuffix = year != null ? ' ($year)' : '';
    Share.share(
      '${content.title}$yearSuffix\n$typeLabel\n$shareLink',
    );
  }

  /// Get the appropriate year for sharing:
  /// - Movies: release year
  /// - TV shows: latest season's air date year
  String? _getShareYear(ContentDetail content) {
    if (content.isMovie) {
      return content.releaseYear?.toString();
    }
    // For TV: try to get the latest season's air date year
    if (content.tmdbSeasons != null && content.tmdbSeasons!.isNotEmpty) {
      final sortedSeasons = content.tmdbSeasons!
          .where((s) => s.seasonNumber > 0 && s.airDate != null && s.airDate!.length >= 4)
          .toList()
        ..sort((a, b) => b.seasonNumber.compareTo(a.seasonNumber));
      if (sortedSeasons.isNotEmpty) {
        return sortedSeasons.first.airDate!.substring(0, 4);
      }
    }
    // Fallback to the show's first air date year
    return content.releaseYear?.toString();
  }

  // ─── Actors Section ────────────────────────────────────────────────────────
  Widget _buildActorsSection(List<CastMember> cast) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cast',
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8)),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: ListView.builder(
            physics: const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            itemBuilder: (context, index) {
              final actor = cast[index];
              final imageUrl = actor.profilePath != null
                  ? 'https://image.tmdb.org/t/p/w185${actor.profilePath}'
                  : null;

              return Padding(
                padding:
                    EdgeInsets.only(right: index < cast.length - 1 ? 10 : 0),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(actorModalProvider.notifier).state =
                        ActorModalState(
                      isOpen: true,
                      actorId: actor.id,
                      actorName: actor.name,
                      characterName: actor.character,
                      profilePath: actor.profilePath,
                    );
                  },
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        // Avatar — rounded square, portrait ratio
                        Container(
                          width: 76,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.border.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.person_rounded,
                                          color: AppColors.textMuted, size: 28),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.person_rounded,
                                          color: AppColors.textMuted, size: 28),
                                    ),
                                  )
                                : Container(
                                    color: AppColors.surfaceElevated,
                                    child: const Icon(Icons.person_rounded,
                                        color: AppColors.textMuted, size: 28),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Actor name
                        Text(
                          actor.name,
                          style: GoogleFonts.inter(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        // Character name
                        if (actor.character != null &&
                            actor.character!.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            actor.character!,
                            style: GoogleFonts.inter(
                                color: AppColors.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
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
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: -0.5,
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
    return Consumer(builder: (context, ref, _) {
      // 1. Fetch episodes directly from Nextdrive selector page
      final postUrl = content.postUrl ??
          MovieSiteScraperService.instance.getPostUrl(content.id) ??
          MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
          '';

      final nextdriveAsync = ref.watch(nextdriveEpisodesProvider(
        NextdriveEpisodeParams(
          tmdbId: content.id,
          title: content.title,
          seasonNumber: _selectedSeason,
          postUrl: postUrl,
          posterUrl: content.posterUrl,
        ),
      ));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSeasonSearchRow(content),
          const SizedBox(height: 16),
          nextdriveAsync.when(
            data: (nextdriveEps) {
              if (nextdriveEps.isNotEmpty) {
                final filtered = _filterNextdriveEpisodes(nextdriveEps);
                if (filtered.isEmpty) {
                  return _buildEmptyTab(Icons.tv_off_rounded, 'No matching episodes');
                }
                return Column(
                  children: filtered
                      .map((ep) => _buildNextdriveEpisodeCard(ep, content))
                      .toList(),
                );
              }
              return _buildEmptyTab(Icons.tv_off_rounded,
                  'No episodes available on Nextdrive for Season $_selectedSeason');
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
            ),
            error: (err, _) => _buildEmptyTab(Icons.error_outline,
                'Could not load episodes for Season $_selectedSeason'),
          ),
        ],
      );
    });
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
            physics: const ClampingScrollPhysics(),
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
        context.push('/details/${item.mediaType}/${item.id}');
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
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
    final mediaType = content.isTv ? 'tv' : 'movie';
    final deepLink = DeepLinkService.buildShareLink(mediaType, content.id);
    final year = _getShareYear(content);
    final typeLabel = content.isTv ? 'Season' : 'Movie';
    final yearSuffix = year != null ? ' ($year)' : '';
    final shareText = '${content.title}$yearSuffix\n$typeLabel\n$deepLink';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            // ── Preview Card ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Poster Thumbnail
                  if (content.posterUrl != null && content.posterUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: content.posterUrl!.startsWith('http')
                            ? content.posterUrl!
                            : 'https://image.tmdb.org/t/p/w200${content.posterUrl}',
                        width: 56,
                        height: 80,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 56, height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.movie, color: AppColors.textMuted, size: 24),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 56, height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.movie, color: AppColors.textMuted, size: 24),
                    ),
                  const SizedBox(width: 14),
                  // Title & Share Message
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content.title,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share this ${content.isTv ? 'series' : 'movie'} with friends',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Divider ──
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.white.withValues(alpha: 0.05),
            ),

            // ── Action Buttons ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  // Copy Deep Link
                  Expanded(
                    child: _ShareCardButton(
                      icon: Icons.link_rounded,
                      label: 'Copy Link',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Clipboard.setData(ClipboardData(text: deepLink));
                        CustomToast.show(context, 'Link copied!', type: ToastType.success, icon: Icons.check_rounded);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Share
                  Expanded(
                    child: _ShareCardButton(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      isPrimary: true,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Share.share(shareText);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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



  Widget _buildSeasonSearchRow(ContentDetail content, {Map<int, List<int>>? streamingSeasonMap}) {
    // Use streaming JSON seasons if available, otherwise fall back to content model
    final seasonNums = (streamingSeasonMap != null && streamingSeasonMap.isNotEmpty)
        ? (streamingSeasonMap.keys.toList()..sort())
        : content.seasonNumbers;

    // Ensure _selectedSeason is valid
    final currentSeason = seasonNums.contains(_selectedSeason)
        ? _selectedSeason
        : seasonNums.first;

    return Row(
      children: [
        // Season dropdown button
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          clipBehavior: Clip.hardEdge,
          child: StickyDropdownModal<int>(
            items: seasonNums,
            value: currentSeason,
            onChanged: (result) {
              if (result != _selectedSeason) {
                setState(() => _selectedSeason = result);
              }
            },
            itemLabelBuilder: (seasonNum) => 'Season $seasonNum',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Season $currentSeason',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary, size: 20),
                ],
              ),
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
    final hasPlayLink = true;
    final epNum = episode.episodeNumber ?? 0;

    return PressableScale(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Play area: thumbnail + episode info ──
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: hasPlayLink
                    ? () => _handlePlay(
                        season: _selectedSeason, episode: epNum)
                    : () => _showToastError(
                        'No play link available for ${episode.title}'),
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
                                : (content.posterUrl != null && content.posterUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: content.posterUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) =>
                                            Container(color: AppColors.surfaceElevated),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppColors.surfaceElevated,
                                          child: const Icon(Icons.play_circle_fill,
                                              color: AppColors.textMuted, size: 32),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.surfaceElevated,
                                        child: const Icon(Icons.play_circle_fill,
                                            color: AppColors.textMuted, size: 32),
                                      )),
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
                  ],
                ),
              ),
            ),

            // Vertical Divider
            Container(
              height: 40,
              width: 1,
              color: Colors.white10,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),

            // Download button — state-aware (idle / downloading / done)
            StreamBuilder<DownloadItem>(
              stream: DownloadManager.instance.updateStream,
              builder: (context, _) {
                final match = DownloadManager.instance.downloads.cast<DownloadItem?>().firstWhere(
                  (d) => d!.title == content.title && d.season == _selectedSeason && d.episode == epNum,
                  orElse: () => null,
                );
                final isPaused = match != null && match.status == DownloadStatus.paused;
                final isActiveDownload = match != null &&
                    (match.status == DownloadStatus.downloading ||
                     match.status == DownloadStatus.pending ||
                     match.status == DownloadStatus.converting ||
                     match.status == DownloadStatus.paused);
                final isCompleted = match != null && match.status == DownloadStatus.completed;
                final progress = match?.progress ?? 0.0;

                if (isCompleted) {
                  // ── Green checkmark ──
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      CustomToast.show(context, 'Already Downloaded', type: ToastType.success);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 1.2),
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                    ),
                  );
                }

                if (isActiveDownload) {
                  // ── Animated progress ring with pause/resume + percentage ──
                  final pctText = (progress * 100).toStringAsFixed(2);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (match!.is10Gbps) {
                        CustomToast.show(context, 'Pause/resume not supported for this link', type: ToastType.warning);
                        return;
                      }
                      if (isPaused) {
                        DownloadManager.instance.resumeDownload(match.id);
                      } else if (match.status == DownloadStatus.downloading) {
                        DownloadManager.instance.pauseDownload(match.id);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  value: (match?.status == DownloadStatus.pending) ? null : progress,
                                  strokeWidth: 2.5,
                                  color: isPaused ? Colors.orangeAccent : AppColors.primary,
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              Icon(
                                match?.is10Gbps == true
                                    ? Icons.arrow_downward_rounded
                                    : (isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                                color: (isPaused ? Colors.orangeAccent : AppColors.primary).withValues(alpha: 0.7),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pctText%',
                          style: TextStyle(
                            color: isPaused ? Colors.orangeAccent : AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // ── Default download button ──
                return GestureDetector(
                  onTap: hasPlayLink
                      ? () => _startDownload(epNum, content, episodeRuntime: episode.runtime)
                      : () => _showToastError('No play/download link available'),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hasPlayLink ? AppColors.surfaceElevated : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasPlayLink ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.download_rounded,
                      color: hasPlayLink ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.3),
                      size: 22,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<NextdriveEpisode> _filterNextdriveEpisodes(List<NextdriveEpisode> episodes) {
    if (_episodeSearch.isEmpty) return episodes;
    final q = _episodeSearch.toLowerCase();
    return episodes.where((ep) => ep.title.toLowerCase().contains(q)).toList();
  }

  Widget _buildNextdriveEpisodeCard(NextdriveEpisode episode, ContentDetail content) {
    final epNum = episode.episodeNumber ?? episode.index;
    String badgeText;
    if (episode.rangeStart != null) {
      badgeText = 'E${episode.rangeStart}-${episode.rangeEnd}';
    } else if (episode.isComplete) {
      badgeText = 'Full';
    } else {
      badgeText = 'E$epNum';
    }

    return PressableScale(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Play area: thumbnail + Nextdrive episode title ──
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleNextdrivePlay(episode, content),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Thumbnail with episode badge
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
                                : (content.posterUrl != null &&
                                        content.posterUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: content.posterUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                            color: AppColors.surfaceElevated),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppColors.surfaceElevated,
                                          child: const Icon(
                                              Icons.play_circle_fill,
                                              color: AppColors.textMuted,
                                              size: 32),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.surfaceElevated,
                                        child: const Icon(
                                            Icons.play_circle_fill,
                                            color: AppColors.textMuted,
                                            size: 32),
                                      )),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(badgeText,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Episode info: STRICTLY NEXTDRIVE PAGE TITLE
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            episode.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Vertical Divider
            Container(
              height: 40,
              width: 1,
              color: Colors.white10,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),

            // Download button — state-aware
            StreamBuilder<DownloadItem>(
              stream: DownloadManager.instance.updateStream,
              builder: (context, _) {
                final match = DownloadManager.instance.downloads
                    .cast<DownloadItem?>()
                    .firstWhere(
                      (d) =>
                          d!.title.contains(content.title) &&
                          d.season == _selectedSeason &&
                          d.episode == epNum,
                      orElse: () => null,
                    );
                final isPaused =
                    match != null && match.status == DownloadStatus.paused;
                final isActiveDownload = match != null &&
                    (match.status == DownloadStatus.downloading ||
                        match.status == DownloadStatus.pending ||
                        match.status == DownloadStatus.converting ||
                        match.status == DownloadStatus.paused);
                final isCompleted =
                    match != null && match.status == DownloadStatus.completed;
                final progress = match?.progress ?? 0.0;

                if (isCompleted) {
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      CustomToast.show(context, 'Already Downloaded',
                          type: ToastType.success);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.4),
                            width: 1.2),
                      ),
                      child: const Icon(Icons.check_circle_rounded,
                          color: Colors.greenAccent, size: 22),
                    ),
                  );
                }

                if (isActiveDownload) {
                  final pctText = (progress * 100).toStringAsFixed(2);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (match!.is10Gbps) {
                        CustomToast.show(context, 'Pause/resume not supported for this link', type: ToastType.warning);
                        return;
                      }
                      if (isPaused) {
                        DownloadManager.instance.resumeDownload(match.id);
                      } else if (match.status == DownloadStatus.downloading) {
                        DownloadManager.instance.pauseDownload(match.id);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  value: (match?.status == DownloadStatus.pending)
                                      ? null
                                      : progress,
                                  strokeWidth: 2.5,
                                  color: isPaused
                                      ? Colors.orangeAccent
                                      : AppColors.primary,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              Icon(
                                match?.is10Gbps == true
                                    ? Icons.arrow_downward_rounded
                                    : (isPaused
                                        ? Icons.play_arrow_rounded
                                        : Icons.pause_rounded),
                                color: (isPaused
                                        ? Colors.orangeAccent
                                        : AppColors.primary)
                                    .withValues(alpha: 0.7),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pctText%',
                          style: TextStyle(
                            color: isPaused
                                ? Colors.orangeAccent
                                : AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GestureDetector(
                  onTap: () => _startDownload(
                    episode.episodeNumber ?? episode.index,
                    content,
                    episodeRuntime: content.runtime,
                    nextdriveVcloudUrl: episode.vcloudUrl,
                    nextdriveAltUrls: episode.alternativeUrls,
                    episode: episode,
                  ),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Handles online streaming for Nextdrive episode with strict policy:
  /// Prioritize FSLv2 > FSL (STRICTLY NO 10Gbps link).
  /// If neither is available, show dialog asking user to download.
  /// Shows a cinematic fullscreen loading overlay with backdrop, title and
  /// description while resolving the VCloud stream link.
  Future<void> _handleNextdrivePlay(
      NextdriveEpisode episode, ContentDetail content) async {
    HapticFeedback.lightImpact();

    // Build display title: "Content Title - Episode X" or "Content Title"
    final displayTitle = '${content.title} — ${episode.title}';

    // Use content backdrop or poster for the cinematic overlay
    final backdropImageUrl = content.backdropUrl != null &&
            content.backdropUrl!.isNotEmpty
        ? (content.backdropUrl!.startsWith('/')
            ? 'https://image.tmdb.org/t/p/w1280${content.backdropUrl}'
            : content.backdropUrl!)
        : content.posterUrl;

    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => VideoPlayerScreen(
          url: '',
          title: displayTitle,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          year: content.releaseYear,
          imdbId: content.imdbId,
          season: _selectedSeason,
          episode: episode.episodeNumber ?? episode.index,
          posterUrl: episode.thumbnailUrl ?? content.posterUrl,
          backdropUrl: backdropImageUrl,
          logoUrl: content.logoUrl ?? content.tmdbLogoUrl,
          description: content.overview,
          streamResolver: () async {
            // Instant 0ms playback if 720p direct stream is already pre-resolved!
            if (episode.preResolvedStream?.canStreamOnline == true &&
                episode.preResolvedStream?.onlineStreamUrl != null) {
              debugPrint(
                  '[Play] Using pre-resolved 720p direct link for Ep ${episode.episodeNumber ?? episode.index}');
              return episode.preResolvedStream!.onlineStreamUrl!;
            }

            var postUrl = content.postUrl ??
                MovieSiteScraperService.instance.getPostUrl(content.id) ??
                MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
                '';
            final epNum = episode.episodeNumber ?? episode.index;

            // Query SeriesVcloudRepository for cached/on-demand stream
            if (postUrl.isNotEmpty) {
              final vStream = await SeriesVcloudRepository.instance.resolvePlaybackStream(
                postKey: postUrl,
                seasonNumber: _selectedSeason,
                episodeNumber: epNum,
                preferredQuality: '720p',
              );
              if (vStream != null && vStream.isNotEmpty) {
                return vStream;
              }
            }

            var res = await SitePostExtractor.instance.resolveVcloudStream(
              episode.vcloudUrl,
              alternativeUrls: episode.alternativeUrls,
            );
            episode.preResolvedStream = res;
            if (res.fileSize != null && res.fileSize!.isNotEmpty) {
              episode.exactSize = res.fileSize;
            }
            if (res.canStreamOnline && res.onlineStreamUrl != null) {
              return res.onlineStreamUrl!;
            }

            // Fallback: If primary had no playable stream, check companion buttons (G-Direct, etc.)
            try {
              if (postUrl.isEmpty) {
                postUrl = await SitePostExtractor.instance.findPostUrl(
                  title: content.title,
                  tmdbId: widget.tmdbId,
                  year: content.releaseYear,
                  imdbId: content.imdbId,
                ) ?? '';
              }
              if (postUrl.isNotEmpty) {
                final buttons =
                    await SitePostExtractor.instance.extractPostButtons(postUrl);
                final sNum = _selectedSeason;
                final altButtons = buttons
                    .where((b) =>
                        b.seasonNumber == sNum &&
                        !b.isBatchZip &&
                        b.href != episode.vcloudUrl)
                    .toList();
                for (final btn in altButtons) {
                  final altEps = await SitePostExtractor.instance
                      .extractNextdriveEpisodes(btn.href);
                  final matched = altEps
                      .where((e) => (e.episodeNumber ?? e.index) == epNum)
                      .firstOrNull;
                  if (matched != null) {
                    final altRes =
                        await SitePostExtractor.instance.resolveVcloudStream(
                      matched.vcloudUrl,
                      alternativeUrls: matched.alternativeUrls,
                    );
                    if (altRes.canStreamOnline &&
                        altRes.onlineStreamUrl != null) {
                      return altRes.onlineStreamUrl!;
                    }
                  }
                }
              }
            } catch (_) {}

            return null;
          },
          initialResolutionMap: {
            '720p': episode.vcloudUrl,
            if (episode.otherResolutions != null) ...episode.otherResolutions!,
          },
          resolutionMapResolver: () async {
            final epNum = episode.episodeNumber ?? episode.index;
            var postUrl = content.postUrl ??
                MovieSiteScraperService.instance.getPostUrl(content.id) ??
                MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
                '';
            // 1. Instant check in SeriesVcloudRepository
            if (postUrl.isNotEmpty) {
              final vEp = SeriesVcloudRepository.instance.getEpisode(postUrl, _selectedSeason, epNum);
              if (vEp != null && vEp.vcloudUrls.isNotEmpty) {
                return Map<String, String>.from(vEp.vcloudUrls);
              }
            }
            if (episode.otherResolutions != null && episode.otherResolutions!.isNotEmpty) {
              return {'720p': episode.vcloudUrl, ...episode.otherResolutions!};
            }
            // 2. Try fast GitHub DB (~200ms)
            try {
              final dbMap = await VcloudExtractorService().fetchResolutionLinksMap(
                tmdbId: widget.tmdbId,
                mediaType: 'tv',
                title: content.title,
                season: _selectedSeason,
                episode: epNum,
              );
              if (dbMap.isNotEmpty) return dbMap;
            } catch (_) {}

            // 3. Fallback to SitePostExtractor across season buttons
            try {
              if (postUrl.isEmpty) {
                postUrl = await SitePostExtractor.instance.findPostUrl(
                  title: content.title,
                  tmdbId: widget.tmdbId,
                  year: content.releaseYear,
                  imdbId: content.imdbId,
                ) ?? '';
              }
              if (postUrl.isNotEmpty) {
                final res = await SitePostExtractor.instance
                    .getAvailableResolutionsForContent(
                  postUrl: postUrl,
                  isMovie: false,
                  seasonNumber: _selectedSeason,
                  episodeNumber: epNum,
                );
                if (res.isNotEmpty) return res;
              }
            } catch (_) {}
            return {'720p': episode.vcloudUrl};
          },
        ),
      ),
    );
  }

  /// Handles download for Nextdrive episode.
  Future<void> _handleNextdriveDownload(
      NextdriveEpisode episode, ContentDetail content) async {
    HapticFeedback.mediumImpact();
    CustomToast.show(context, 'Resolving download link...',
        type: ToastType.info);

    try {
      final res =
          await SitePostExtractor.instance.resolveVcloudStream(
        episode.vcloudUrl,
        alternativeUrls: episode.alternativeUrls,
      );
      final downloadUrl = res.bestDownloadUrl;

      if (!mounted) return;

      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        final item = await DownloadManager.instance.startDownload(
          url: downloadUrl,
          title: '${content.title} ${episode.title}',
          season: _selectedSeason,
          episode: episode.episodeNumber ?? episode.index,
          posterUrl: episode.thumbnailUrl ?? content.posterUrl,
          context: context,
          fileExtension: downloadUrl.contains('.zip') ? 'zip' : 'mkv',
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          providerName: 'V-Cloud',
        );
        if (item != null && mounted) {
          _showDownloadStartedToast(item);
        }
      } else {
        _showToastError('Could not resolve direct download link.');
      }
    } catch (e) {
      if (mounted) {
        _showToastError('Download error: $e');
      }
    }
  }

  /// Displays dialog when online streaming is unavailable (no FSLv2 or FSL).
  void _showOnlinePlaybackUnavailableDialog({
    required ContentDetail content,
    required String episodeTitle,
    required VoidCallback onDownload,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16161E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.orangeAccent, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Online Streaming Unavailable',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            'Online fast streaming (FSLv2 / FSL) is currently unavailable for $episodeTitle.\n\nDirect download is available for this title. Would you like to download it now?',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onDownload();
              },
              child: const Text('Download Now',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
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
    int episodeNumber,
    ContentDetail content, {
    int? episodeRuntime,
    String? nextdriveVcloudUrl,
    List<String>? nextdriveAltUrls,
    NextdriveEpisode? episode,
  }) async {
    HapticFeedback.mediumImpact();

    if (!mounted) return;

    final actualRuntime = episodeRuntime ?? content.runtime;

    // Look up in SeriesVcloudRepository if available
    final postUrl = content.postUrl ??
        MovieSiteScraperService.instance.getPostUrl(content.id) ??
        MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
        '';
    final targetSeason = content.isMovie ? 1 : _selectedSeason;
    final targetEpNum = (episodeNumber > 0) ? episodeNumber : (episode?.episodeNumber ?? episode?.index ?? 1);

    SeriesVcloudEpisode? vcloudEp;
    if (content.isTv && postUrl.isNotEmpty) {
      vcloudEp = SeriesVcloudRepository.instance.getEpisode(postUrl, targetSeason, targetEpNum);
    }

    // 1. Seed resolutions map & sizes directly if episode or URL is provided
    Map<String, String> resMap = {};
    Map<String, String> initialSizes = {};

    if (vcloudEp != null && vcloudEp.hasAnyVcloudUrl) {
      resMap.addAll(vcloudEp.vcloudUrls);
      initialSizes.addAll(vcloudEp.exactSizes);
    } else if (episode != null) {
      if (episode.vcloudUrl.isNotEmpty) {
        resMap['720p'] = episode.vcloudUrl;
      }
      if (episode.exactSize != null && episode.exactSize!.isNotEmpty) {
        initialSizes['720p'] = episode.exactSize!;
      }
      if (episode.otherResolutions != null) {
        resMap.addAll(episode.otherResolutions!);
      }
      if (episode.otherResolutionSizes != null) {
        initialSizes.addAll(episode.otherResolutionSizes!);
      }
    } else if (nextdriveVcloudUrl != null && nextdriveVcloudUrl.isNotEmpty) {
      resMap['720p'] = nextdriveVcloudUrl;
    }

    final hasDirectSeed = resMap.isNotEmpty;

    // 2. Open quality selector sheet: IMMEDIATELY isLoading: false if we have 720p seeded!
    showQualitySelectorSheet(
      context: context,
      ref: ref,
      m3u8Url: '',
      title: content.title,
      isLoading: !hasDirectSeed,
      season: content.isMovie ? null : _selectedSeason,
      episode: content.isMovie ? null : episodeNumber,
      isMovie: content.isMovie,
      fallbackQuality: content.result,
      fallbackLanguage: content.language,
      runtime: actualRuntime,
    );

    if (hasDirectSeed) {
      final sortedRes = resMap.keys.toList()
        ..sort((a, b) {
          final aNum = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final bNum = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
          return bNum.compareTo(aNum);
        });

      ref.read(downloadModalProvider.notifier).update((state) => state.copyWith(
        isLoading: false,
        availableResolutions: sortedRes,
        resolutionUrls: resMap,
        resolutionSizes: initialSizes,
        onSelectResolution: (chosenRes) => _executeDownloadResolution(
          chosenRes: chosenRes,
          content: content,
          episodeNumber: targetEpNum,
          actualRuntime: actualRuntime,
          nextdriveVcloudUrl: nextdriveVcloudUrl,
          nextdriveAltUrls: nextdriveAltUrls,
          episode: episode,
        ),
      ));

      // Asynchronously fetch missing exact sizes for all seeded qualities in parallel
      for (final entry in resMap.entries) {
        if (!initialSizes.containsKey(entry.key)) {
          SitePostExtractor.instance
              .extractExactFileSizeFromVcloud(entry.value)
              .then((sz) {
            if (sz != null && sz.isNotEmpty && mounted) {
              final cur = Map<String, String>.from(
                ref.read(downloadModalProvider).resolutionSizes ?? {},
              );
              cur[entry.key] = sz;
              if (episode != null) {
                if (entry.key == '720p') episode.exactSize = sz;
                episode.otherResolutionSizes ??= {};
                episode.otherResolutionSizes![entry.key] = sz;
              }
              if (vcloudEp != null) {
                vcloudEp.exactSizes[entry.key] = sz;
              }
              ref.read(downloadModalProvider.notifier).update(
                    (s) => s.copyWith(resolutionSizes: cur),
                  );
            }
          });
        }
      }

      // Asynchronously fetch any missing resolutions (1080p, 480p) for TV series
      if (content.isTv && (!resMap.containsKey('1080p') || !resMap.containsKey('480p'))) {
        _asyncFetchOtherResolutions(
          content: content,
          seasonNumber: _selectedSeason,
          episodeNumber: targetEpNum,
          actualRuntime: actualRuntime,
          nextdriveVcloudUrl: nextdriveVcloudUrl,
          nextdriveAltUrls: nextdriveAltUrls,
          targetEpisode: episode,
        );
      }
      return;
    }

    // Fallback if not seeded (e.g. Movies or non-Nextdrive TV)
    try {
      final dbMap = await VcloudExtractorService().fetchResolutionLinksMap(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        title: content.title,
        season: content.isMovie ? null : _selectedSeason,
        episode: content.isMovie ? null : episodeNumber,
      ).timeout(const Duration(seconds: 2), onTimeout: () => {});
      if (dbMap.isNotEmpty) {
        resMap.addAll(dbMap);
      }
    } catch (e) {
      debugPrint('[Download] Error fetching VCloud resolution map: $e');
    }

    if (resMap.isEmpty) {
      try {
        var postUrl = content.postUrl ??
            MovieSiteScraperService.instance.getPostUrl(content.id) ??
            MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
            '';
        if (postUrl.isEmpty) {
          postUrl = await SitePostExtractor.instance.findPostUrl(
            title: content.title,
            tmdbId: widget.tmdbId,
            year: content.releaseYear,
            imdbId: content.imdbId,
          ) ?? '';
        }
        if (postUrl.isNotEmpty) {
          final fetched = await SitePostExtractor.instance.getAvailableResolutionsForContent(
            postUrl: postUrl,
            isMovie: content.isMovie,
            seasonNumber: content.isMovie ? null : _selectedSeason,
            episodeNumber: content.isMovie ? null : episodeNumber,
          );
          if (fetched.isNotEmpty) {
            resMap.addAll(fetched);
          }
        }
      } catch (e) {
        debugPrint('[Download] Error getting resolutions: $e');
      }
    }

    if (!mounted) return;

    if (resMap.isEmpty) {
      debugPrint('[Download] No download sources found.');
      ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
      _showToastError('No download sources found.');
      return;
    }

    final sortedRes = resMap.keys.toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
        final bNum = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
        return bNum.compareTo(aNum);
      });

    ref.read(downloadModalProvider.notifier).update((state) => state.copyWith(
      isLoading: false,
      availableResolutions: sortedRes,
      resolutionUrls: resMap,
      resolutionSizes: const {},
      onSelectResolution: (chosenRes) => _executeDownloadResolution(
        chosenRes: chosenRes,
        content: content,
        episodeNumber: episodeNumber,
        actualRuntime: actualRuntime,
        nextdriveVcloudUrl: nextdriveVcloudUrl,
        nextdriveAltUrls: nextdriveAltUrls,
        episode: episode,
      ),
    ));

    // Asynchronously fetch exact file sizes
    for (final entry in resMap.entries) {
      SitePostExtractor.instance
          .extractExactFileSizeFromVcloud(entry.value)
          .then((exactSize) {
        if (exactSize != null && exactSize.isNotEmpty && mounted) {
          final cur = Map<String, String>.from(
            ref.read(downloadModalProvider).resolutionSizes ?? {},
          );
          cur[entry.key] = exactSize;
          ref.read(downloadModalProvider.notifier).update(
                (s) => s.copyWith(resolutionSizes: cur),
              );
        }
      });
    }
  }

  void _asyncFetchOtherResolutions({
    required ContentDetail content,
    required int seasonNumber,
    required int episodeNumber,
    int? actualRuntime,
    String? nextdriveVcloudUrl,
    List<String>? nextdriveAltUrls,
    NextdriveEpisode? targetEpisode,
  }) async {
    try {
      var postUrl = content.postUrl ??
          MovieSiteScraperService.instance.getPostUrl(content.id) ??
          MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
          '';
      if (postUrl.isEmpty) {
        postUrl = await SitePostExtractor.instance.findPostUrl(
          title: content.title,
          tmdbId: widget.tmdbId,
          year: content.releaseYear,
          imdbId: content.imdbId,
        ) ?? '';
      }
      if (postUrl.isEmpty) return;

      final otherMap = await SitePostExtractor.instance.fetchOtherResolutionsForEpisode(
        postUrl: postUrl,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        currentQuality: '720p',
        targetEpisode: targetEpisode,
      );

      if (otherMap.isNotEmpty && mounted) {
        final curResMap = Map<String, String>.from(
          ref.read(downloadModalProvider).resolutionUrls ?? {},
        );
        curResMap.addAll(otherMap);

        final sortedRes = curResMap.keys.toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
            final bNum = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
            return bNum.compareTo(aNum);
          });

        final curSizes = Map<String, String>.from(
          ref.read(downloadModalProvider).resolutionSizes ?? {},
        );
        if (targetEpisode?.otherResolutionSizes != null) {
          curSizes.addAll(targetEpisode!.otherResolutionSizes!);
        }

        ref.read(downloadModalProvider.notifier).update((s) => s.copyWith(
          availableResolutions: sortedRes,
          resolutionUrls: curResMap,
          resolutionSizes: curSizes,
        ));

        // Asynchronously fetch any missing sizes for newly added resolutions
        for (final entry in otherMap.entries) {
          if (!curSizes.containsKey(entry.key)) {
            SitePostExtractor.instance
                .extractExactFileSizeFromVcloud(entry.value)
                .then((sz) {
              if (sz != null && sz.isNotEmpty && mounted) {
                final updated = Map<String, String>.from(
                  ref.read(downloadModalProvider).resolutionSizes ?? {},
                );
                updated[entry.key] = sz;
                if (targetEpisode != null) {
                  targetEpisode.otherResolutionSizes ??= {};
                  targetEpisode.otherResolutionSizes![entry.key] = sz;
                }
                ref.read(downloadModalProvider.notifier).update(
                  (s) => s.copyWith(resolutionSizes: updated),
                );
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[Download] Error async fetching other resolutions: $e');
    }
  }

  Future<void> _executeDownloadResolution({
    required String chosenRes,
    required ContentDetail content,
    required int episodeNumber,
    int? actualRuntime,
    String? nextdriveVcloudUrl,
    List<String>? nextdriveAltUrls,
    NextdriveEpisode? episode,
  }) async {
    ref.read(downloadModalProvider.notifier).update(
      (s) => s.copyWith(extractingResolution: chosenRes),
    );

    final modalState = ref.read(downloadModalProvider);
    final targetUrl = modalState.resolutionUrls?[chosenRes] ??
        (chosenRes == '720p' ? (episode?.vcloudUrl ?? nextdriveVcloudUrl) : null);

    if (targetUrl == null || targetUrl.isEmpty) {
      if (mounted) {
        ref.read(downloadModalProvider.notifier).update(
          (s) => s.copyWith(extractingResolution: null),
        );
        _showToastError('No link available for $chosenRes');
      }
      return;
    }

    String? downloadUrl;
    String providerName = 'V-Cloud';
    String? extractedSize;

    // Fast-path: if 720p was chosen and already pre-resolved, use it in 0ms!
    if (chosenRes == '720p' && episode?.preResolvedStream != null) {
      final pre = episode!.preResolvedStream!;
      if (pre.bestDownloadUrl != null && pre.bestDownloadUrl!.isNotEmpty) {
        downloadUrl = pre.bestDownloadUrl;
        extractedSize = pre.fileSize ?? episode.exactSize;
        if (pre.fslv2Url != null && pre.fslv2Url!.isNotEmpty) {
          providerName = 'FSLv2 Server';
        } else if (pre.fslUrl != null && pre.fslUrl!.isNotEmpty) {
          providerName = 'FSL Server';
        } else if (pre.fastDlUrl != null && pre.fastDlUrl!.isNotEmpty) {
          providerName = 'FastDL Server';
        } else if (pre.tenGbpsUrl != null && pre.tenGbpsUrl!.isNotEmpty) {
          providerName = '10Gbps Server';
        } else if (pre.pixeldrainUrl != null && pre.pixeldrainUrl!.isNotEmpty) {
          providerName = 'PixelDrain Server';
        }
        debugPrint('[Download] Instant 0ms pre-resolved download link for 720p: $downloadUrl');
      }
    }

    if (downloadUrl == null) {
      try {
        final altUrls = (targetUrl == (episode?.vcloudUrl ?? nextdriveVcloudUrl))
            ? (episode?.alternativeUrls ?? nextdriveAltUrls)
            : null;
        final streamRes = await SitePostExtractor.instance.resolveVcloudStream(
          targetUrl,
          alternativeUrls: altUrls,
        );
        extractedSize = streamRes.fileSize;

        if (streamRes.fslv2Url != null && streamRes.fslv2Url!.isNotEmpty) {
          downloadUrl = streamRes.fslv2Url;
          providerName = 'FSLv2 Server';
        } else if (streamRes.fslUrl != null && streamRes.fslUrl!.isNotEmpty) {
          downloadUrl = streamRes.fslUrl;
          providerName = 'FSL Server';
        } else if (streamRes.fastDlUrl != null && streamRes.fastDlUrl!.isNotEmpty) {
          downloadUrl = streamRes.fastDlUrl;
          providerName = 'FastDL Server';
        } else if (streamRes.tenGbpsUrl != null && streamRes.tenGbpsUrl!.isNotEmpty) {
          downloadUrl = streamRes.tenGbpsUrl;
          providerName = '10Gbps Server';
        } else if (streamRes.pixeldrainUrl != null && streamRes.pixeldrainUrl!.isNotEmpty) {
          downloadUrl = streamRes.pixeldrainUrl;
          providerName = 'PixelDrain Server';
        }
      } catch (e) {
        debugPrint('[Download] Error extracting direct link for $chosenRes: $e');
      }
    }

    if (!mounted) return;

    // Fallback to VcloudExtractorService if SitePostExtractor didn't yield a link
    if (downloadUrl == null || downloadUrl.isEmpty) {
      try {
        final servers = await VcloudExtractorService().extractVcloud(targetUrl);
        if (servers.containsKey('Server 2') && servers['Server 2']!.isNotEmpty) {
          downloadUrl = servers['Server 2'];
          providerName = 'FSLv2 Server';
        } else if (servers.containsKey('Server 1') && servers['Server 1']!.isNotEmpty) {
          downloadUrl = servers['Server 1'];
          providerName = 'FSL Server';
        } else if (servers.containsKey('PixelServer') && servers['PixelServer']!.isNotEmpty) {
          downloadUrl = servers['PixelServer'];
          providerName = 'PixelDrain Server';
        }
      } catch (e) {
        debugPrint('[Download] Fallback extractVcloud error: $e');
      }
    }

    if (downloadUrl == null || downloadUrl.isEmpty) {
      ref.read(downloadModalProvider.notifier).update(
        (s) => s.copyWith(extractingResolution: null),
      );
      _showToastError('Could not extract download link for $chosenRes.');
      return;
    }

    final exactSize = ref.read(downloadModalProvider).resolutionSizes?[chosenRes] ?? extractedSize;
    final fileSizeBytes = SitePostExtractor.parseBytesFromSizeString(exactSize);

    // Close modal
    ref.read(downloadModalProvider.notifier).state = const DownloadModalState();

    final downloadTitle = '${content.title} $chosenRes DanieWatch';

    try {
      final item = await DownloadManager.instance.startDownload(
        url: downloadUrl,
        title: downloadTitle,
        season: content.isMovie ? 0 : _selectedSeason,
        episode: content.isMovie ? 0 : episodeNumber,
        posterUrl: content.posterUrl,
        context: context,
        fileExtension: downloadUrl.contains('.zip') ? 'zip' : 'mkv',
        runtime: actualRuntime,
        qualityLabel: chosenRes,
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        providerName: providerName,
        originalEmbedUrl: targetUrl,
        fileSizeBytes: fileSizeBytes,
      );
      if (item != null && mounted) {
        CustomToast.show(
          context,
          'Download started',
          type: ToastType.info,
          icon: Icons.download_done_rounded,
        );
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
  Future<void> _handlePlay({int? season, int? episode}) async {
    HapticFeedback.lightImpact();

    final content = ref.read(detailProvider(_detailParams)).valueOrNull;
    if (content == null) return;

    // Check if this item is from the 3rd party hosted index
    final manifestItems = ref.read(localManifestItemsProvider).valueOrNull ?? [];
    final manifestItem = manifestItems.where((m) => m.id == widget.tmdbId).firstOrNull;
    final bool is3rdParty = manifestItem?.is3rdPartyHosted ?? false;

    // For movies: try to resolve VCloud link directly (FSLv2 > FSL)
    if (content.isMovie) {
      // Build backdrop URL for cinematic overlay
      final backdropImageUrl = content.backdropUrl != null &&
              content.backdropUrl!.isNotEmpty
          ? (content.backdropUrl!.startsWith('/')
              ? 'https://image.tmdb.org/t/p/w1280${content.backdropUrl}'
              : content.backdropUrl!)
          : content.posterUrl;

      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => VideoPlayerScreen(
            url: '',
            title: content.title,
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            year: content.releaseYear,
            imdbId: content.imdbId,
            posterUrl: content.posterUrl,
            backdropUrl: backdropImageUrl,
            logoUrl: content.logoUrl ?? content.tmdbLogoUrl,
            description: content.overview,
            isDirectLink: false,
            is3rdPartyHosted: is3rdParty,
            streamResolver: () async {
              var postUrl = content.postUrl ??
                  MovieSiteScraperService.instance.getPostUrl(content.id) ??
                  MovieSiteScraperService.instance.getPostUrl(widget.tmdbId);
              if (postUrl == null || postUrl.isEmpty) {
                postUrl = await SitePostExtractor.instance.findPostUrl(
                  title: content.title,
                  tmdbId: widget.tmdbId,
                  year: content.releaseYear,
                );
              }

              if (postUrl != null && postUrl.isNotEmpty) {
                final buttons = await SitePostExtractor.instance.extractPostButtons(postUrl);
                // Filter non-batch buttons
                final nonBatch = buttons.where((b) => !b.isBatchZip).toList();
                if (nonBatch.isNotEmpty) {
                  SitePostButton? pickMovieQuality(String q) {
                    final matches = nonBatch
                        .where((b) => b.quality.toLowerCase() == q.toLowerCase())
                        .toList();
                    if (matches.isEmpty) return null;
                    return matches.firstWhere(
                      (b) {
                        final t = b.text.toLowerCase();
                        final h = b.href.toLowerCase();
                        return t.contains('v-cloud') ||
                            t.contains('vcloud') ||
                            t.contains('resumable') ||
                            h.contains('vcloud');
                      },
                      orElse: () => matches.first,
                    );
                  }

                  final bestBtn = pickMovieQuality('720p') ??
                      pickMovieQuality('480p') ??
                      pickMovieQuality('1080p') ??
                      pickMovieQuality('2160p') ??
                      nonBatch.first;

                  String targetVcloudUrl = bestBtn.href;
                  List<String> altUrls = [];

                  // If it's a Nextdrive / VGMLink / FastDL landing page, extract the movie VCloud link from it!
                  final lowerHref = bestBtn.href.toLowerCase();
                  if (lowerHref.contains('nexdrive') ||
                      lowerHref.contains('vgmlink') ||
                      lowerHref.contains('fastdl') ||
                      lowerHref.contains('gdflix') ||
                      lowerHref.contains('filebee')) {
                    try {
                      final landingVcloud = await SitePostExtractor.instance
                          .extractVcloudFromLandingPublic(bestBtn.href);
                      if (landingVcloud != null && landingVcloud.isNotEmpty) {
                        targetVcloudUrl = landingVcloud;
                      } else {
                        final episodes = await SitePostExtractor.instance
                            .extractNextdriveEpisodes(bestBtn.href);
                        if (episodes.isNotEmpty) {
                          targetVcloudUrl = episodes.first.vcloudUrl;
                          altUrls = episodes.first.alternativeUrls;
                        }
                      }
                    } catch (e) {
                      debugPrint('[DetailsScreen] Movie Nextdrive extract error: $e');
                    }
                  }

                  // Resolve VCloud direct stream (strictly FSLv2 > FSL, NEVER 10Gbps online)
                  try {
                    final res = await SitePostExtractor.instance.resolveVcloudStream(
                      targetVcloudUrl,
                      alternativeUrls: altUrls,
                    );
                    if (res.canStreamOnline && res.onlineStreamUrl != null) {
                      return res.onlineStreamUrl!; // Strictly FSLv2 > FSL
                    }
                  } catch (e) {
                    debugPrint('[DetailsScreen] Movie resolveVcloudStream error: $e');
                  }
                }
              }

              // Fallback: Check GitHub streaming database for Movie (prioritize 720p > 480p > 1080p)
              try {
                final vcloudLinks = await VcloudExtractorService().fetchResolutionLinksMap(
                  tmdbId: widget.tmdbId,
                  mediaType: 'movie',
                  title: content.title,
                );
                if (vcloudLinks.isNotEmpty) {
                  final vUrl = vcloudLinks['720p'] ??
                      vcloudLinks['480p'] ??
                      vcloudLinks['1080p'] ??
                      vcloudLinks.values.first;
                  final servers = await VcloudExtractorService().extractVcloud(vUrl);
                  // Strictly check Server 2 (FSLv2) > Server 1 (FSL), NEVER Server 3 (10Gbps)
                  if (servers.containsKey('Server 2') && servers['Server 2']!.isNotEmpty) {
                    return servers['Server 2']!;
                  }
                  if (servers.containsKey('Server 1') && servers['Server 1']!.isNotEmpty) {
                    return servers['Server 1']!;
                  }
                  for (final entry in servers.entries) {
                    final key = entry.key.toLowerCase();
                    final val = entry.value.toLowerCase();
                    if ((key.contains('fslv2') || key.contains('fsl') || key.contains('direct')) &&
                        !key.contains('10gbps') &&
                        !val.contains('hubcloud') &&
                        !val.contains('gpdl')) {
                      return entry.value;
                    }
                  }
                }
              } catch (e) {
                debugPrint('[DetailsScreen] Movie VCloud DB fallback error: $e');
              }
              return null;
            },
            resolutionMapResolver: () async {
              // 1. Try fast GitHub DB (~200ms)
              try {
                final dbMap = await VcloudExtractorService().fetchResolutionLinksMap(
                  tmdbId: widget.tmdbId,
                  mediaType: content.isMovie ? 'movie' : 'tv',
                  title: content.title,
                  season: content.isMovie ? null : _selectedSeason,
                  episode: content.isMovie ? null : 1,
                );
                if (dbMap.isNotEmpty) return dbMap;
              } catch (_) {}

              // 2. Fallback: SitePostExtractor
              try {
                var postUrl = content.postUrl ??
                    MovieSiteScraperService.instance.getPostUrl(content.id) ??
                    MovieSiteScraperService.instance.getPostUrl(widget.tmdbId);
                if (postUrl == null || postUrl.isEmpty) {
                  postUrl = await SitePostExtractor.instance.findPostUrl(
                    title: content.title,
                    tmdbId: widget.tmdbId,
                    year: content.releaseYear,
                  );
                }
                if (postUrl != null && postUrl.isNotEmpty) {
                  return await SitePostExtractor.instance.getAvailableResolutionsForContent(
                    postUrl: postUrl,
                    isMovie: content.isMovie,
                    seasonNumber: _selectedSeason,
                    episodeNumber: 1,
                  );
                }
              } catch (_) {}
              return {};
            },
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    // For TV series: resolve VCloud link for the target episode (or episode 1 of selected season)
    if (content.isTv) {
      final postUrl = content.postUrl ??
          MovieSiteScraperService.instance.getPostUrl(content.id) ??
          MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
          '';
      final targetSeason = season ?? _selectedSeason;
      final targetEpNum = episode ?? 1;
      final epParams = NextdriveEpisodeParams(
        tmdbId: content.id,
        title: content.title,
        seasonNumber: targetSeason,
        postUrl: postUrl,
        posterUrl: content.posterUrl,
      );

      // Build backdrop URL for cinematic overlay
      final backdropImageUrl = content.backdropUrl != null &&
              content.backdropUrl!.isNotEmpty
          ? (content.backdropUrl!.startsWith('/')
              ? 'https://image.tmdb.org/t/p/w1280${content.backdropUrl}'
              : content.backdropUrl!)
          : content.posterUrl;

      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => VideoPlayerScreen(
            url: '',
            title: '${content.title} — S${targetSeason.toString().padLeft(2, '0')}E${targetEpNum.toString().padLeft(2, '0')}',
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            year: content.releaseYear,
            imdbId: content.imdbId,
            seasons: content.seasonNumbers,
            season: targetSeason,
            episode: targetEpNum,
            posterUrl: content.posterUrl,
            backdropUrl: backdropImageUrl,
            logoUrl: content.logoUrl ?? content.tmdbLogoUrl,
            description: content.overview,
            isDirectLink: false,
            is3rdPartyHosted: is3rdParty,
            streamResolver: () async {
              List<NextdriveEpisode> episodes =
                  ref.read(nextdriveEpisodesProvider(epParams)).valueOrNull ?? [];
              if (episodes.isEmpty) {
                episodes = await ref.refresh(nextdriveEpisodesProvider(epParams).future);
              }

              if (episodes.isNotEmpty) {
                final targetEp = (episode != null && episode > 0)
                    ? episodes.firstWhere(
                        (e) => (e.episodeNumber ?? e.index) == episode,
                        orElse: () => episodes.first)
                    : episodes.first;

                // 0ms instant playback if pre-resolved!
                if (targetEp.preResolvedStream?.canStreamOnline == true &&
                    targetEp.preResolvedStream?.onlineStreamUrl != null) {
                  debugPrint(
                      '[Play] Using pre-resolved 720p direct link for Ep ${targetEp.episodeNumber ?? targetEp.index}');
                  return targetEp.preResolvedStream!.onlineStreamUrl!;
                }

                final res = await SitePostExtractor.instance.resolveVcloudStream(
                  targetEp.vcloudUrl,
                  alternativeUrls: targetEp.alternativeUrls,
                );
                targetEp.preResolvedStream = res;
                if (res.fileSize != null && res.fileSize!.isNotEmpty) {
                  targetEp.exactSize = res.fileSize;
                }
                if (res.canStreamOnline && res.onlineStreamUrl != null) {
                  return res.onlineStreamUrl!;
                }
              }

              // Fallback: Check GitHub streaming database for TV episode (prioritize 720p > 480p > 1080p)
              try {
                final vcloudLinks = await VcloudExtractorService().fetchResolutionLinksMap(
                  tmdbId: widget.tmdbId,
                  mediaType: 'tv',
                  title: content.title,
                  season: targetSeason,
                  episode: targetEpNum,
                );
                if (vcloudLinks.isNotEmpty) {
                  final vUrl = vcloudLinks['720p'] ??
                      vcloudLinks['480p'] ??
                      vcloudLinks['1080p'] ??
                      vcloudLinks.values.first;
                  final servers = await VcloudExtractorService().extractVcloud(vUrl);
                  // Strictly check Server 2 (FSLv2) > Server 1 (FSL), NEVER Server 3 (10Gbps)
                  if (servers.containsKey('Server 2') && servers['Server 2']!.isNotEmpty) {
                    return servers['Server 2']!;
                  }
                  if (servers.containsKey('Server 1') && servers['Server 1']!.isNotEmpty) {
                    return servers['Server 1']!;
                  }
                  for (final entry in servers.entries) {
                    final key = entry.key.toLowerCase();
                    final val = entry.value.toLowerCase();
                    if ((key.contains('fslv2') || key.contains('fsl') || key.contains('direct')) &&
                        !key.contains('10gbps') &&
                        !val.contains('hubcloud') &&
                        !val.contains('gpdl')) {
                      return entry.value;
                    }
                  }
                }
              } catch (e) {
                debugPrint('[DetailsScreen] TV VCloud DB fallback error: $e');
              }
              return null;
            },
            resolutionMapResolver: () async {
              // 1. Try fast GitHub DB (~200ms)
              try {
                final dbMap = await VcloudExtractorService().fetchResolutionLinksMap(
                  tmdbId: widget.tmdbId,
                  mediaType: 'tv',
                  title: content.title,
                  season: targetSeason,
                  episode: targetEpNum,
                );
                if (dbMap.isNotEmpty) return dbMap;
              } catch (_) {}

              // 2. Fallback to SitePostExtractor across season buttons
              try {
                var postUrl = content.postUrl ??
                    MovieSiteScraperService.instance.getPostUrl(content.id) ??
                    MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
                    '';
                if (postUrl.isEmpty) {
                  postUrl = await SitePostExtractor.instance.findPostUrl(
                    title: content.title,
                    tmdbId: widget.tmdbId,
                    year: content.releaseYear,
                    imdbId: content.imdbId,
                  ) ?? '';
                }
                if (postUrl.isNotEmpty) {
                  return await SitePostExtractor.instance.getAvailableResolutionsForContent(
                    postUrl: postUrl,
                    isMovie: false,
                    seasonNumber: targetSeason,
                    episodeNumber: targetEpNum,
                  );
                }
              } catch (_) {}
              return {};
            },
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    final backdropImageUrl = content.backdropUrl != null &&
            content.backdropUrl!.isNotEmpty
        ? (content.backdropUrl!.startsWith('/')
            ? 'https://image.tmdb.org/t/p/w1280${content.backdropUrl}'
            : content.backdropUrl!)
        : content.posterUrl;

    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => VideoPlayerScreen(
          url: '',
          title: content.title,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          year: content.releaseYear,
          imdbId: content.imdbId,
          seasons: content.seasonNumbers,
          season: season,
          episode: episode,
          posterUrl: content.posterUrl,
          backdropUrl: backdropImageUrl,
          logoUrl: content.logoUrl ?? content.tmdbLogoUrl,
          description: content.overview,
          isDirectLink: false,
          is3rdPartyHosted: is3rdParty,
          resolutionMapResolver: () async {
            try {
              final dbMap = await VcloudExtractorService().fetchResolutionLinksMap(
                tmdbId: widget.tmdbId,
                mediaType: content.isMovie ? 'movie' : 'tv',
                title: content.title,
                season: content.isMovie ? null : season,
                episode: content.isMovie ? null : episode,
              );
              if (dbMap.isNotEmpty) return dbMap;
            } catch (_) {}

            try {
              var postUrl = content.postUrl ??
                  MovieSiteScraperService.instance.getPostUrl(content.id) ??
                  MovieSiteScraperService.instance.getPostUrl(widget.tmdbId) ??
                  '';
              if (postUrl.isEmpty) {
                postUrl = await SitePostExtractor.instance.findPostUrl(
                  title: content.title,
                  tmdbId: widget.tmdbId,
                  year: content.releaseYear,
                  imdbId: content.imdbId,
                ) ?? '';
              }
              if (postUrl.isNotEmpty) {
                return await SitePostExtractor.instance.getAvailableResolutionsForContent(
                  postUrl: postUrl,
                  isMovie: content.isMovie,
                  seasonNumber: season,
                  episodeNumber: episode,
                );
              }
            } catch (_) {}
            return {};
          },
        ),
      ),
    );
  }


  Future<void> _handleDownload(String url) async {
    HapticFeedback.mediumImpact();
    final content = ref.read(detailProvider(_detailParams)).valueOrNull;
    if (content != null) {
      _startDownload(0, content);
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
    final cleanMessage = message == 'Content not found'
        ? 'No Data Available'
        : 'Something went wrong';
    final description = message == 'Content not found'
        ? 'We couldn\'t find any details for this title on TMDB. It might not be indexed or details are temporarily unavailable.'
        : 'An error occurred while fetching details. Please check your network and try again.';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Back Button
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  padding: const EdgeInsets.all(12),
                ),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            
            // Central Content
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Glowing Icon Container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            blurRadius: 24,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.movie_creation_outlined,
                        color: AppColors.primary,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Title
                    Text(
                      cleanMessage,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Description
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 36),
                    
                    // Action Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Retry button
                        Flexible(
                          child: Container(
                            height: 50,
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: ElevatedButton(
                              onPressed: () => ref.invalidate(detailProvider(_detailParams)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                'Retry',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Back home button
                        Flexible(
                          child: Container(
                            height: 50,
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                'Go Back',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Loading Skeleton ──────────────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Shimmer.fromColors(
        baseColor: AppColors.surface,
        highlightColor: AppColors.surfaceElevated,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
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
                        physics: const ClampingScrollPhysics(),
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

/// Pill-shaped button used inside the share tab card.
class _ShareCardButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ShareCardButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary
              ? AppColors.primary
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: isPrimary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isPrimary
                    ? Colors.white
                    : AppColors.textSecondary,
                size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary
                    ? Colors.white
                    : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
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
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final wobble = t > 0
              ? 1.0 + math.sin(t * math.pi * 3) * (1.0 - t) * 0.08
              : 1.0;
          return Transform.scale(
            scale: wobble,
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
  bool _isPageLoaded = false;

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
  // CSS to hide YouTube's UI and force the video to fill the viewport
  static const String _ytPureCss = r'''
    (function() {
      var style = document.getElementById('daniewatch-styles');
      if (!style) {
        style = document.createElement('style');
        style.id = 'daniewatch-styles';
        document.head.appendChild(style);
      }
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
          overflow: hidden !important; background: #000000 !important;
        }
        .player-container, #player, #movie_player,
        .html5-video-container {
          position: fixed !important;
          top: 0 !important; left: 0 !important;
          width: 100vw !important; height: 100vh !important;
          max-height: 100vh !important; min-height: 100vh !important;
          z-index: 99999 !important; object-fit: cover !important;
          background: #000000 !important;
        }
        video {
          position: fixed !important;
          top: 50% !important; left: 50% !important;
          min-width: 100vw !important; min-height: 100vh !important;
          width: auto !important; height: auto !important;
          z-index: 99999 !important; object-fit: cover !important;
          transform: translate(-50%, -50%) scale(1.5) !important;
          background: #000000 !important;
        }
        ytm-app, ytm-watch { overflow: hidden !important; }
      `;
    })();
  ''';

  // Logic to handle initial autoplay (muted)
  static const String _ytInitialPlaybackJs = r'''
    (function() {
      function tryAutoplay() {
        var video = document.querySelector('video');
        if (video) {
          video.muted = true;
          video.volume = 0;
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
        var initInterval = setInterval(function() {
          attempts++;
          if (tryAutoplay() || attempts > 30) clearInterval(initInterval);
        }, 500);
      }
    })();
  ''';

  void _toggleMute() {
    if (_webViewController == null || !_hasTrailer) return;
    setState(() {
      _isMuted = !_isMuted;
    });

    _webViewController!.evaluateJavascript(source: '''
      (function() {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(v) {
          v.muted = ${_isMuted};
          v.volume = ${_isMuted ? 0 : 1};
          // Explicitly call play case it paused during mute/unmute
          if (!${_isMuted}) v.play().catch(function(){});
        });
        
        var player = document.getElementById('movie_player');
        if (player) {
          if (${_isMuted}) {
            if (typeof player.mute === 'function') player.mute();
            if (typeof player.setVolume === 'function') player.setVolume(0);
          } else {
            if (typeof player.unMute === 'function') player.unMute();
            if (typeof player.setVolume === 'function') player.setVolume(100);
          }
        }
      })();
    ''');
    HapticFeedback.selectionClick();
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
                            useHybridComposition: false,
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
                            if (mounted) {
                              setState(() => _isPageLoaded = true);
                            }
                            // Apply CSS and start initial playback logic
                            await controller.evaluateJavascript(source: _ytPureCss);
                            await controller.evaluateJavascript(source: _ytInitialPlaybackJs);
                            
                            // Re-apply ONLY CSS after 2 seconds to catch any late-injected elements
                            // without resetting the mute/volume state.
                            Future.delayed(const Duration(milliseconds: 2000), () {
                              if (mounted) controller.evaluateJavascript(source: _ytPureCss);
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
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.7),
                      Colors.black.withValues(alpha: 0.95),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.15, 0.5, 0.75, 0.85, 0.92, 1.0],
                  ),
                ),
              ),
            ),
          ),


          // ── Mute/Unmute Button (top-right) ──
          if (_hasTrailer && _trailerReady && _isPageLoaded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: LiquidTapEffect(
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

