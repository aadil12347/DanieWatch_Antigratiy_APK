// lib/presentation/widgets/quality_selector_sheet.dart
// ─────────────────────────────────────────────────────────
// Bottom sheet that shows all available qualities,
// audio tracks, and subtitles.
// ─────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../services/m3u8_parser.dart';
import '../providers/download_modal_provider.dart';

// ── What the user selected ────────────────────────────────
class DownloadSelection {
  final StreamVariant quality;
  final AudioTrack? audioTrack;
  final SubtitleTrack? subtitleTrack;
  final String title;

  DownloadSelection({
    required this.quality,
    this.audioTrack,
    this.subtitleTrack,
    required this.title,
  });
}

// ── Show the sheet ────────────────────────────────────────
Future<DownloadSelection?> showQualitySelectorSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String m3u8Url,
  required String title,
  bool isLoading = false,
  int? season,
  int? episode,
  bool isMovie = false,
  String? fallbackQuality,
  String? fallbackLanguage,
}) async {
  final currentState = ref.read(downloadModalProvider);
  if (currentState.isOpen) {
    currentState.onCancel?.call();
    ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
    await Future.delayed(const Duration(milliseconds: 150));
  }

  final completer = Completer<DownloadSelection?>();

  ref.read(downloadModalProvider.notifier).state = DownloadModalState(
    isOpen: true,
    isLoading: isLoading,
    m3u8Url: m3u8Url,
    title: title,
    season: season,
    episode: episode,
    isMovie: isMovie,
    fallbackQuality: fallbackQuality,
    fallbackLanguage: fallbackLanguage,
    onSelected: (sel) {
      ref.read(downloadModalProvider.notifier).state =
          const DownloadModalState();
      if (!completer.isCompleted) completer.complete(sel);
    },
    onCancel: () {
      ref.read(downloadModalProvider.notifier).state =
          const DownloadModalState();
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  return completer.future;
}

class QualitySelectorContent extends ConsumerStatefulWidget {
  final String m3u8Url;
  final String title;
  final void Function(DownloadSelection) onSelected;
  final VoidCallback onCancel;

  const QualitySelectorContent({
    super.key,
    required this.m3u8Url,
    required this.title,
    required this.onSelected,
    required this.onCancel,
  });

  @override
  ConsumerState<QualitySelectorContent> createState() =>
      _QualitySelectorContentState();
}

class _QualitySelectorContentState
    extends ConsumerState<QualitySelectorContent> {
  PlaylistInfo? _playlist;
  bool _internalLoading = true;
  String? _error;

  StreamVariant? _selectedVariant;
  AudioTrack? _selectedAudio;
  SubtitleTrack? _selectedSubtitle;
  bool _downloadSubtitles = false;

  @override
  void initState() {
    super.initState();
    if (widget.m3u8Url.isNotEmpty) {
      _loadPlaylist();
    }
  }

  @override
  void didUpdateWidget(QualitySelectorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.m3u8Url != oldWidget.m3u8Url && widget.m3u8Url.isNotEmpty) {
      if (mounted) {
        setState(() {
          _internalLoading = true;
          _error = null;
        });
      }
      _loadPlaylist();
    }
  }

  Future<void> _loadPlaylist() async {
    try {
      final parser = M3u8Parser();
      final info = await parser.parse(widget.m3u8Url);
      if (mounted) {
        setState(() {
          _playlist = info;
          // Apply defaulting logic from PlaylistInfo
          _selectedVariant = info.defaultVariant;
          _selectedAudio = info.defaultAudio;
          _selectedSubtitle = null; // Subtitles off by default
          _internalLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _internalLoading = false;
        });
      }
    }
  }

  String _mapNativeToEnglish(String? input) {
    if (input == null) return '';
    final mapping = {
      // ISO Codes
      'hi': 'Hindi',
      'hin': 'Hindi',
      'en': 'English',
      'eng': 'English',
      'ko': 'Korean',
      'kor': 'Korean',
      'ja': 'Japanese',
      'jpn': 'Japanese',
      'es': 'Spanish',
      'spa': 'Spanish',
      'fr': 'French',
      'fra': 'French',
      'ar': 'Arabic',
      'ara': 'Arabic',
      'it': 'Italian',
      'ita': 'Italian',
      'de': 'German',
      'deu': 'German',
      'pt': 'Portuguese',
      'por': 'Portuguese',
      'ru': 'Russian',
      'rus': 'Russian',
      'zh': 'Chinese',
      'zho': 'Chinese',
      'ta': 'Tamil',
      'tam': 'Tamil',
      'te': 'Telugu',
      'tel': 'Telugu',
      'ml': 'Malayalam',
      'mal': 'Malayalam',
      'kn': 'Kannada',
      'kan': 'Kannada',
      // Native Names
      'हिन्दी': 'Hindi',
      'हिंदी': 'Hindi',
      '한국어': 'Korean',
      '日本語': 'Japanese',
      'español': 'Spanish',
      'français': 'French',
      'العربية': 'Arabic',
      'தமிழ்': 'Tamil',
      'తెలుగు': 'Telugu',
      'മലയാളം': 'Malayalam',
      'ಕನ್ನಡ': 'Kannada',
    };

    final trimmed = input.trim();
    if (mapping.containsKey(trimmed)) return mapping[trimmed]!;
    
    final lower = trimmed.toLowerCase();
    if (mapping.containsKey(lower)) return mapping[lower]!;
    
    return trimmed;
  }

  String _getAudioDisplayName(AudioTrack track) {
    // Parser's displayName is like "🇮🇳 हिन्दी"
    // We want "🇮🇳 Hindi"
    
    // 1. Try to map the ISO code (e.g. 'hi')
    String englishName = _mapNativeToEnglish(track.language);
    
    // 2. If mapping didn't change anything (or it was already English), 
    // and name is a native name, try mapping the name
    if (englishName == track.language || englishName == 'English') {
       final nameMapped = _mapNativeToEnglish(track.name);
       if (nameMapped != track.name) {
         englishName = nameMapped;
       } else {
         englishName = track.name; // Fallback to raw name
       }
    }
    
    // 3. Re-attach the flag using the track's logic if possible, 
    // or just use the parser's logic for flags
    final flag = track.displayName.split(' ').first;
    return '$flag $englishName';
  }

  @override
  Widget build(BuildContext context) {
    final modalState = ref.watch(downloadModalProvider);
    final isLoading = modalState.isLoading || _internalLoading;

    return Container(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fix: Only show S0 E0 for non-movies and if season/episode > 0
                      if (!modalState.isMovie && 
                          modalState.season != null && 
                          modalState.episode != null &&
                          modalState.season! > 0)
                        Text(
                          'SEASON ${modalState.season} · EPISODE ${modalState.episode}',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      Text(
                        widget.title,
                        style: GoogleFonts.lora(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_selectedVariant != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Estimated Size: ${_selectedVariant!.estimatedSize}',
                            style: GoogleFonts.inter(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _TactileCloseButton(onTap: widget.onCancel),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 32),

          if (isLoading)
            _buildSkeleton()
          else if (_error != null)
            _buildError()
          else ...[
            _buildSelectors(),
            const SizedBox(height: 16),
            _buildDownloadButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          children: [
            Row(
              children: List.generate(
                  3,
                  (i) => Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 80,
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      )),
            ),
            const SizedBox(height: 24),
            ...List.generate(
                2,
                (i) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    )),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          const Text('Extraction failed',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onSelected(DownloadSelection(
                quality: StreamVariant(url: widget.m3u8Url, bandwidth: 0),
                audioTrack: null,
                title: widget.title,
                subtitleTrack: null,
              )),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Download Original'),
            ),
          ),
        ],
      ),
    );
  }

  String _getVariantDisplayLabel(StreamVariant v) {
    final playlist = _playlist;
    if (playlist == null) return v.badgeLabel;

    final sortedVariants = List<StreamVariant>.from(playlist.variants)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    final uniqueResolutions = sortedVariants.map((sv) => sv.qualityLabel).toSet();
    final isSingleResolution = uniqueResolutions.length <= 1;
    final fbq = ref.read(downloadModalProvider).fallbackQuality;
    final index = sortedVariants.indexWhere((sv) => sv.url == v.url);

    if (isSingleResolution) {
      String label;
      if (index == 0) {
        label = '720p';
      } else if (index == 1) {
        label = '480p';
      } else if (index == 2) {
        label = '360p';
      } else {
        label = v.qualityLabel;
      }

      if (sortedVariants.length == 1 && fbq != null) {
        final upperFbq = fbq.toUpperCase();
        if (upperFbq == 'FHD') return '1080p';
        if (upperFbq == 'HD') return '720p';
        if (upperFbq == 'SD') return '480p';
        if (fbq.contains('p')) return fbq;
      }
      return label;
    } else {
      return v.badgeLabel.replaceAll(' HD', '').replaceAll('SD', 'Original');
    }
  }

  Widget _buildSelectors() {
    final playlist = _playlist!;

    // Sort variants for consistent display
    final sortedVariants = List<StreamVariant>.from(playlist.variants)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quality
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('SELECT QUALITY',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: sortedVariants.length,
            itemBuilder: (_, i) {
              final v = sortedVariants[i];
              final isSelected = _selectedVariant == v;
              final displayLabel = _getVariantDisplayLabel(v);

              return GestureDetector(
                onTap: () => setState(() => _selectedVariant = v),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    displayLabel,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        if (playlist.audioTracks.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('AUDIO TRACK',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
          ...playlist.audioTracks.map((track) {
            final isSelected = _selectedAudio == track;
            
            // Fallback logic for language
            String displayLabel = _getAudioDisplayName(track);
            if (playlist.audioTracks.length == 1 && ref.read(downloadModalProvider).fallbackLanguage != null) {
              displayLabel = _mapNativeToEnglish(ref.read(downloadModalProvider).fallbackLanguage!);
            }

            return GestureDetector(
              onTap: () => setState(() => _selectedAudio = track),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  children: [
                    Text(displayLabel,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],

        if (playlist.subtitles.isNotEmpty) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SUBTITLES',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                      SizedBox(height: 4),
                      Text('Include subtitles in download',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
                Switch(
                  value: _downloadSubtitles,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() {
                      _downloadSubtitles = val;
                      _selectedSubtitle = val ? playlist.subtitles.first : null;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDownloadButton() {
    String buttonLabel = 'Start Download';
    if (_selectedVariant != null) {
      final parts = <String>[];
      if (_selectedAudio != null) {
        final audioName = _getAudioDisplayName(_selectedAudio!);
        final cleanName = audioName.replaceAll(RegExp(r'[^\w\s]'), '').trim();
        if (cleanName.isNotEmpty) parts.add(cleanName);
      }
      final quality = _getVariantDisplayLabel(_selectedVariant!);
      parts.add(quality);
      
      if (_selectedSubtitle != null) {
        parts.add('+ Sub');
      }
      
      buttonLabel = 'Download · ${parts.join(" ")}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _selectedVariant != null
              ? () {
                  widget.onSelected(DownloadSelection(
                    quality: _selectedVariant!,
                    audioTrack: _selectedAudio,
                    subtitleTrack: _selectedSubtitle,
                    title: widget.title,
                  ));
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.border.withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: Text(buttonLabel,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _TactileCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TactileCloseButton({required this.onTap});

  @override
  State<_TactileCloseButton> createState() => _TactileCloseButtonState();
}

class _TactileCloseButtonState extends State<_TactileCloseButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        scale: _isPressed ? 0.85 : 1.0,
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
            child: const Icon(Icons.close, color: Colors.white70, size: 18),
          ),
        ),
      ),
    );
  }
}
