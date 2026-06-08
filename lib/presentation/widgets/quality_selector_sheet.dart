// lib/presentation/widgets/quality_selector_sheet.dart
// ─────────────────────────────────────────────────────────
// Bottom sheet that shows all available qualities,
// audio tracks, and subtitles.
// ─────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../services/m3u8_parser.dart';
import '../../services/peachify_extractor.dart';
import '../../core/utils/error_sanitizer.dart';
import '../../core/utils/toast_utils.dart';
import '../providers/download_modal_provider.dart';

// ── What the user selected ────────────────────────────────
// ── What the user selected ────────────────────────────────
class DownloadSelection {
  final StreamVariant quality;
  final AudioTrack? audioTrack;
  final SubtitleTrack? subtitleTrack;
  final String title;
  final String masterUrl;
  final Map<String, String>? headers;
  final String? providerName;

  DownloadSelection({
    required this.quality,
    this.audioTrack,
    this.subtitleTrack,
    required this.title,
    required this.masterUrl,
    this.headers,
    this.providerName,
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
  int? runtime,
  List<PeachifyStream>? streams,
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
    runtime: runtime,
    streams: streams,
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
  PeachifyStream? _selectedStream;
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
      _internalLoading = true;
      _loadPlaylistFromUrl(widget.m3u8Url);
    } else {
      _internalLoading = false;
    }
  }

  @override
  void didUpdateWidget(QualitySelectorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.m3u8Url != oldWidget.m3u8Url && widget.m3u8Url.isNotEmpty) {
      if (mounted) {
        setState(() {
          _internalLoading = true;
          _selectedStream = null;
          _playlist = null;
          _error = null;
        });
      }
      _loadPlaylistFromUrl(widget.m3u8Url);
    }
  }

  PlaylistInfo? _parseMockPlaylist(String url) {
    if (!url.startsWith('mock_vcloud://')) return null;
    try {
      final payload = url.substring('mock_vcloud://'.length);
      final decodedJson = utf8.decode(base64Decode(payload));
      final Map<String, dynamic> resMap = jsonDecode(decodedJson);
      
      final List<StreamVariant> variants = [];
      resMap.forEach((res, streamUrl) {
        int bandwidth = 1500000; // default 720p
        String resSize = "1280x720";
        if (res.contains('1080')) {
          bandwidth = 3000000;
          resSize = "1920x1080";
        } else if (res.contains('480')) {
          bandwidth = 800000;
          resSize = "854x480";
        } else if (res.contains('360')) {
          bandwidth = 400000;
          resSize = "640x360";
        } else if (res.contains('2160') || res.contains('4k')) {
          bandwidth = 8000000;
          resSize = "3840x2160";
        }
        variants.add(StreamVariant(
          url: streamUrl.toString(),
          bandwidth: bandwidth,
          resolution: resSize,
        ));
      });
      
      // Sort variants best to worst
      variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      
      return PlaylistInfo(
        variants: variants,
        audioTracks: [],
        subtitles: [],
        isMasterPlaylist: true,
      );
    } catch (e) {
      debugPrint('[QualitySelector] Error parsing mock vcloud payload: $e');
      return null;
    }
  }

  Future<void> _loadPlaylistFromUrl(String url) async {
    final mockPlaylist = _parseMockPlaylist(url);
    if (mockPlaylist != null) {
      if (mounted) {
        setState(() {
          _playlist = mockPlaylist;
          _selectedAudio = null;
          _selectedVariant = mockPlaylist.defaultVariant;
          _selectedSubtitle = null;
          _internalLoading = false;
        });
      }
      return;
    }

    try {
      final parser = M3u8Parser();
      final info = await parser.parse(url);
      if (mounted) {
        setState(() {
          _playlist = info;
          _selectedAudio = info.defaultAudio;
          final groupVariants = _getFilteredVariants(info, _selectedAudio);
          if (groupVariants.isNotEmpty) {
            _selectedVariant = _getDefaultVariantInGroup(groupVariants);
          } else {
            _selectedVariant = info.defaultVariant;
          }
          _selectedSubtitle = null;
          _internalLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorSanitizer.sanitize(e);
          _internalLoading = false;
        });
      }
    }
  }

  Future<void> _loadPlaylist(PeachifyStream stream) async {
    final mockPlaylist = _parseMockPlaylist(stream.url);
    if (mockPlaylist != null) {
      if (mounted) {
        setState(() {
          _playlist = mockPlaylist;
          _selectedAudio = null;
          _selectedVariant = mockPlaylist.defaultVariant;
          _selectedSubtitle = null;
          _internalLoading = false;
        });
      }
      return;
    }

    try {
      final parser = M3u8Parser();
      final info = await parser.parse(stream.url, headers: stream.headers);
      if (mounted) {
        setState(() {
          _playlist = info;
          _selectedAudio = info.defaultAudio;
          final groupVariants = _getFilteredVariants(info, _selectedAudio);
          if (groupVariants.isNotEmpty) {
            _selectedVariant = _getDefaultVariantInGroup(groupVariants);
          } else {
            _selectedVariant = info.defaultVariant;
          }
          _selectedSubtitle = null;
          _internalLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomToast.show(
          context,
          'Link expired or access denied: ${stream.providerName}',
          type: ToastType.error,
          duration: const Duration(milliseconds: 2500),
        );

        ref.read(downloadModalProvider.notifier).update((state) {
          final currentStreams = state.streams ?? [];
          final filtered = currentStreams.where((s) => s.url != stream.url).toList();
          return state.copyWith(streams: filtered);
        });

        setState(() {
          _selectedStream = null;
          _playlist = null;
          _selectedVariant = null;
          _selectedAudio = null;
          _selectedSubtitle = null;
          _internalLoading = false;
          _error = null;
        });
      }
    }
  }

  List<StreamVariant> _getFilteredVariants(PlaylistInfo playlist, AudioTrack? audio) {
    if (audio == null) return playlist.variants;
    final filtered = playlist.variants.where((v) => v.audioGroupId == audio.groupId).toList();
    if (filtered.isEmpty) {
      return playlist.variants;
    }
    return filtered;
  }

  StreamVariant? _getDefaultVariantInGroup(List<StreamVariant> groupVariants) {
    if (groupVariants.isEmpty) return null;
    if (groupVariants.length == 1) return groupVariants.first;
    try {
      return groupVariants.firstWhere((v) {
        final res = v.resolution ?? '';
        return res.contains('720') || res.contains('1280');
      });
    } catch (_) {
      return groupVariants.first;
    }
  }

  void _onAudioTrackSelected(AudioTrack track) {
    setState(() {
      _selectedAudio = track;
      if (_playlist != null) {
        final groupVariants = _getFilteredVariants(_playlist!, track);
        if (groupVariants.isNotEmpty) {
          _selectedVariant = _getDefaultVariantInGroup(groupVariants);
        }
      }
    });
  }

  String _mapNativeToEnglish(String? input) {
    if (input == null) return '';
    final mapping = {
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
    String englishName = _mapNativeToEnglish(track.language);
    if (englishName == track.language || englishName == 'English') {
       final nameMapped = _mapNativeToEnglish(track.name);
       if (nameMapped != track.name) {
         englishName = nameMapped;
       } else {
         englishName = track.name;
       }
    }
    final flag = track.displayName.split(' ').first;
    return '$flag $englishName';
  }

  @override
  Widget build(BuildContext context) {
    final modalState = ref.watch(downloadModalProvider);
    final isLoading = modalState.isLoading || _internalLoading;
    final streams = modalState.streams ?? [];

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
                if (_selectedStream != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _selectedStream = null;
                        _playlist = null;
                        _selectedVariant = null;
                        _selectedAudio = null;
                        _selectedSubtitle = null;
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      // Season/Episode label below the title
                      if (!modalState.isMovie && 
                          modalState.season != null && 
                          modalState.episode != null &&
                          modalState.season! > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Season ${modalState.season} · Episode ${modalState.episode}',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      // Accurate file size using actual runtime
                      if (_selectedVariant != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Size: ${_selectedVariant!.estimatedSizeForDuration(modalState.runtime)}',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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
          else if (_selectedStream == null)
            _buildStreamsList(streams)
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
                masterUrl: widget.m3u8Url,
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

    final filtered = _getFilteredVariants(playlist, _selectedAudio);
    final sortedVariants = List<StreamVariant>.from(filtered)
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

  Widget _buildStreamsList(List<PeachifyStream> streams) {
    if (streams.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white30, size: 48),
            const SizedBox(height: 16),
            const Text(
              'No active servers available',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'All server links have expired or failed. Please close this modal and try extracting again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('SELECT LANGUAGE / SERVER',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: streams.length,
            itemBuilder: (context, index) {
              final stream = streams[index];
              final displayName = stream.providerName;
              
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _selectedStream = stream;
                    _internalLoading = true;
                    _playlist = null;
                    _error = null;
                  });
                  _loadPlaylist(stream);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.language_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectors() {
    final playlist = _playlist!;
    final filteredVariants = _getFilteredVariants(playlist, _selectedAudio);
    final sortedVariants = List<StreamVariant>.from(filteredVariants)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Audio Track Above Quality
        if (playlist.audioTracks.isNotEmpty) ...[
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
            
            String displayLabel = _getAudioDisplayName(track);
            if (playlist.audioTracks.length == 1 && ref.read(downloadModalProvider).fallbackLanguage != null) {
              displayLabel = _mapNativeToEnglish(ref.read(downloadModalProvider).fallbackLanguage!);
            }

            final resCount = playlist.variants.where((v) => v.audioGroupId == track.groupId).length;
            final resText = resCount > 0 ? ' ($resCount Resolutions)' : '';
            final fullLabel = '$displayLabel$resText';

            return GestureDetector(
              onTap: () => _onAudioTrackSelected(track),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.1)
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isSelected ? Colors.white.withValues(alpha: 0.8) : AppColors.border),
                ),
                child: Row(
                  children: [
                    Text(fullLabel,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          color: Colors.white, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],

        const SizedBox(height: 16),

        // Quality/Resolution
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
                        ? Colors.white.withValues(alpha: 0.15)
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? Colors.white.withValues(alpha: 0.8) : AppColors.border),
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

        // Subtitles
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
                  activeThumbColor: Colors.white,
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
                    masterUrl: _selectedStream?.url ?? widget.m3u8Url,
                    headers: _selectedStream?.headers,
                    providerName: _selectedStream?.providerName,
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
