import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/toast_utils.dart';
import '../../data/local/download_manager.dart';
import '../../domain/models/content_detail.dart';
import '../../services/extraction/site_post_extractor.dart';
import '../providers/batch_zip_modal_provider.dart';
import 'pressable_scale.dart';

/// Batch/Zip download selector that transforms the bottom nav bar.
/// Follows the same pattern as QualitySelectorContent, ConfirmationModalContent, etc.
class BatchZipSelectorContent extends ConsumerStatefulWidget {
  final ContentDetail content;
  final int seasonNumber;
  final String? postUrl;

  const BatchZipSelectorContent({
    super.key,
    required this.content,
    required this.seasonNumber,
    this.postUrl,
  });

  @override
  ConsumerState<BatchZipSelectorContent> createState() =>
      _BatchZipSelectorContentState();
}

class _BatchZipSelectorContentState
    extends ConsumerState<BatchZipSelectorContent> {
  bool _isLoading = true;
  String? _resolvingHref;
  List<SitePostButton> _options = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBatchOptions();
  }

  void _close() {
    ref.read(batchZipModalProvider.notifier).state =
        const BatchZipModalState();
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
          _error = 'Failed to load batch options: $e';
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
      final directZipUrl = await SitePostExtractor.instance
          .resolveBatchZipDirectLink(option.href);

      if (!mounted) return;

      if (directZipUrl != null && directZipUrl.isNotEmpty) {
        final seasonStr = widget.seasonNumber.toString().padLeft(2, '0');
        final batchTitle = '${widget.content.title} Complete S$seasonStr ${option.quality} DanieWatch';
        await DownloadManager.instance.startDownload(
          url: directZipUrl,
          title: batchTitle,
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
          _close();
          CustomToast.show(
            context,
            'Download started',
            type: ToastType.info,
            icon: Icons.download_done_rounded,
          );
        }
      } else {
        setState(() {
          _resolvingHref = null;
        });
        if (mounted) {
          CustomToast.show(
            context,
            'Could not resolve direct zip file link.',
            type: ToastType.error,
          );
        }
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
      key: const ValueKey('batch_zip_modal'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with title and close button
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2EA1CF), Color(0xFFFF19D0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_zip_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S${widget.seasonNumber} Batch / Zip',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Download full season archive',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _close,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white54, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Body: loading, error, or options list
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Checking available archives…',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 22,
                        color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  children: _options.map((opt) {
                    final isResolving = _resolvingHref == opt.href;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PressableScale(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _startBatchDownload(opt),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isResolving
                                    ? AppColors.primary
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Resolution + size text
                                Expanded(
                                  child: Text(
                                    opt.sizeLabel != null
                                        ? '${opt.quality} · ${opt.sizeLabel}'
                                        : opt.quality,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),

                                // Download icon or spinner
                                if (isResolving)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.download_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
