import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/local/download_manager.dart';
import '../../domain/models/content_detail.dart';
import '../../services/extraction/site_post_extractor.dart';
import 'pressable_scale.dart';

class BatchZipModalContent extends StatefulWidget {
  final ContentDetail content;
  final int seasonNumber;
  final String? postUrl;

  const BatchZipModalContent({
    super.key,
    required this.content,
    required this.seasonNumber,
    this.postUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required ContentDetail content,
    required int seasonNumber,
    String? postUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BatchZipModalContent(
        content: content,
        seasonNumber: seasonNumber,
        postUrl: postUrl,
      ),
    );
  }

  @override
  State<BatchZipModalContent> createState() => _BatchZipModalContentState();
}

class _BatchZipModalContentState extends State<BatchZipModalContent> {
  bool _isLoading = true;
  String? _resolvingHref;
  List<SitePostButton> _options = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBatchOptions();
  }

  Future<void> _loadBatchOptions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var postUrl = widget.postUrl;
      if (postUrl == null || postUrl.isEmpty) {
        postUrl = await SitePostExtractor.instance.findPostUrl(
          title: widget.content.title,
          tmdbId: widget.content.id,
          year: widget.content.releaseYear,
        );
      }

      if (postUrl == null || postUrl.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Could not find source post for batch download.';
          });
        }
        return;
      }

      final buttons =
          await SitePostExtractor.instance.extractPostButtons(postUrl);
      var batchButtons = SitePostExtractor.instance
          .getBatchZipOptions(buttons, widget.seasonNumber);

      // If no options strictly matching season, check if any batch zip exists
      if (batchButtons.isEmpty) {
        batchButtons = buttons.where((b) => b.isBatchZip).toList();
      }

      if (mounted) {
        setState(() {
          _options = batchButtons;
          _isLoading = false;
          if (batchButtons.isEmpty) {
            _error =
                'No Batch/Zip archives available for Season ${widget.seasonNumber}.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load batch download options: $e';
        });
      }
    }
  }

  Future<void> _startBatchDownload(SitePostButton option) async {
    if (_resolvingHref != null) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _resolvingHref = option.href;
    });

    try {
      final directZipUrl =
          await SitePostExtractor.instance.resolveBatchZipDirectLink(option.href);

      if (!mounted) return;

      if (directZipUrl != null && directZipUrl.isNotEmpty) {
        final seasonStr = widget.seasonNumber.toString().padLeft(2, '0');
        await DownloadManager.instance.startDownload(
          url: directZipUrl,
          title: '${widget.content.title} S$seasonStr Batch Zip',
          season: widget.seasonNumber,
          episode: 0,
          posterUrl: widget.content.posterUrl,
          context: context,
          fileExtension: 'zip',
          qualityLabel: option.quality,
          tmdbId: widget.content.id,
          mediaType: 'tv',
          providerName: 'V-Cloud Batch',
        );

        if (mounted) {
          Navigator.of(context).pop();
          CustomToast.show(
            context,
            'Batch Zip download started!',
            type: ToastType.success,
            icon: Icons.download_done_rounded,
          );
        }
      } else {
        setState(() {
          _resolvingHref = null;
        });
        CustomToast.show(
          context,
          'Could not resolve direct zip file link.',
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resolvingHref = null;
        });
        CustomToast.show(
          context,
          'Error resolving zip: $e',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13131A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2EA1CF), Color(0xFFFF19D0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2EA1CF).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.folder_zip_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Season ${widget.seasonNumber} Batch / Zip',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Download full season in one zip archive',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Body
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Checking available Batch/Zip archives...',
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 40, color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: _options.map((opt) {
                final isResolving = _resolvingHref == opt.href;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PressableScale(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _startBatchDownload(opt),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isResolving
                                ? AppColors.primary
                                : Colors.white.withValues(alpha: 0.08),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Quality Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                opt.quality.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Label & size
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${opt.quality} Full Season Zip',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (opt.sizeLabel != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Archive size: ${opt.sizeLabel}',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Action icon or spinner
                            if (isResolving)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.download_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
