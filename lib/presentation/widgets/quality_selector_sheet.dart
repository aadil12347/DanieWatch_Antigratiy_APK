// lib/presentation/widgets/quality_selector_sheet.dart
// ─────────────────────────────────────────────────────────
// Bottom sheet that shows all available qualities,
// audio tracks, and subtitles.
// ─────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final String? fileExtension;
  final int? fileSizeBytes;

  DownloadSelection({
    required this.quality,
    this.audioTrack,
    this.subtitleTrack,
    required this.title,
    required this.masterUrl,
    this.headers,
    this.providerName,
    this.fileExtension,
    this.fileSizeBytes,
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
  List<String>? availableResolutions,
  Map<String, String>? resolutionUrls,
  void Function(String resolution)? onSelectResolution,
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
    availableResolutions: availableResolutions,
    resolutionUrls: resolutionUrls,
    onSelectResolution: onSelectResolution,
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

  String? _fetchedSizeText;
  int? _fileSizeBytes;
  String? _resolvedExtension;
  bool _fetchingSize = false;

  Future<void> _fetchActualFileSize(String url, {Map<String, String>? headers}) async {
    if (url.isEmpty) return;
    if (url.startsWith('mock_vcloud://')) return;
    
    if (!mounted) return;
    setState(() {
      _fetchingSize = true;
      _fetchedSizeText = 'Fetching size...';
      _fileSizeBytes = null;
    });

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..badCertificateCallback = (cert, host, port) => true;

      var currentUrl = url;
      var redirectCount = 0;
      HttpClientResponse? response;

      // Try HEAD request first
      while (redirectCount < 5) {
        final request = await client.headUrl(Uri.parse(currentUrl));
        if (headers != null) {
          headers.forEach((k, v) => request.headers.set(k, v));
        } else {
          request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        }
        request.followRedirects = false;
        response = await request.close();

        final location = response.headers.value('location');
        if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
          if (location.startsWith('http')) {
            currentUrl = location;
          } else {
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          }
          redirectCount++;
        } else {
          break;
        }
      }

      // If HEAD fails or returns non-200/non-206, try GET with Range bytes=0-0
      if (response == null || (response.statusCode != 200 && response.statusCode != 206)) {
        redirectCount = 0;
        currentUrl = url;
        while (redirectCount < 5) {
          final request = await client.getUrl(Uri.parse(currentUrl));
          request.headers.set('Range', 'bytes=0-0');
          if (headers != null) {
            headers.forEach((k, v) => request.headers.set(k, v));
          } else {
            request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
          }
          request.followRedirects = false;
          response = await request.close();

          final location = response.headers.value('location');
          if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
            if (location.startsWith('http')) {
              currentUrl = location;
            } else {
              currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            }
            redirectCount++;
          } else {
            break;
          }
        }
      }

      if (response != null && (response.statusCode == 200 || response.statusCode == 206)) {
        int contentLength = response.headers.contentLength;
        
        if (response.statusCode == 206) {
          final contentRange = response.headers.value('content-range');
          if (contentRange != null) {
            final slashIdx = contentRange.lastIndexOf('/');
            if (slashIdx != -1) {
              final totalStr = contentRange.substring(slashIdx + 1).trim();
              final parsedTotal = int.tryParse(totalStr);
              if (parsedTotal != null && parsedTotal > 0) {
                contentLength = parsedTotal;
              }
            }
          }
        }

        final contentType = response.headers.value('content-type');
        final contentDisposition = response.headers.value('content-disposition');
        
        String? ext;
        if (contentDisposition != null) {
          final regExp = RegExp(r'filename="?([^"\s]+)"?');
          final match = regExp.firstMatch(contentDisposition);
          if (match != null) {
            final filename = match.group(1)!;
            final dotIdx = filename.lastIndexOf('.');
            if (dotIdx != -1) {
              ext = filename.substring(dotIdx).toLowerCase();
            }
          }
        }
        
        if (ext == null && contentType != null) {
          if (contentType.contains('matroska') || contentType.contains('mkv')) {
            ext = '.mkv';
          } else if (contentType.contains('mp4')) {
            ext = '.mp4';
          }
        }

        if (contentLength > 0) {
          final double mb = contentLength / (1024 * 1024);
          String sizeStr;
          if (mb >= 1024) {
            sizeStr = '${(mb / 1024).toStringAsFixed(2)} GB';
          } else {
            sizeStr = '${mb.toStringAsFixed(1)} MB';
          }
          if (mounted) {
            setState(() {
              _fileSizeBytes = contentLength;
              _fetchedSizeText = sizeStr;
              _resolvedExtension = ext;
              _fetchingSize = false;
            });
          }
          client.close();
          return;
        }
      }
      client.close();
    } catch (e) {
      debugPrint('[QualitySelector] Error fetching actual file size: $e');
    }

    if (mounted) {
      setState(() {
        _fileSizeBytes = null;
        _fetchedSizeText = null;
        _fetchingSize = false;
      });
    }
  }

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
      variants.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
      
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

  void _onPlaylistLoaded(PlaylistInfo info) {
    if (!mounted) return;
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
      _resolvedExtension = null;
      _fileSizeBytes = null;
      if (_selectedVariant != null && !_selectedVariant!.url.contains('.m3u8')) {
        _fetchedSizeText = 'Fetching size...';
      } else {
        _fetchedSizeText = null;
      }
    });

    if (_selectedVariant != null && !_selectedVariant!.url.contains('.m3u8')) {
      _fetchActualFileSize(_selectedVariant!.url, headers: _selectedStream?.headers);
    }
  }

  Future<void> _loadPlaylistFromUrl(String url) async {
    final mockPlaylist = _parseMockPlaylist(url);
    if (mockPlaylist != null) {
      _onPlaylistLoaded(mockPlaylist);
      return;
    }

    try {
      final parser = M3u8Parser();
      final info = await parser.parse(url);
      _onPlaylistLoaded(info);
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
      _onPlaylistLoaded(mockPlaylist);
      return;
    }

    try {
      final parser = M3u8Parser();
      final info = await parser.parse(stream.url, headers: stream.headers);
      _onPlaylistLoaded(info);
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
      return groupVariants.last;
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
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      padding: const EdgeInsets.only(bottom: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'S${modalState.season} · E${modalState.episode}',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
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
              else if (modalState.availableResolutions != null && modalState.availableResolutions!.isNotEmpty)
                _buildResolutionList(modalState)
              else if (_selectedStream == null)
                _buildStreamsList(streams)
              else ...[
                _buildSelectors(),
                const SizedBox(height: 16),
                _buildDownloadButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: List.generate(
            3,
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              height: 68,
            ),
          ),
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
      ..sort((a, b) => a.bandwidth.compareTo(b.bandwidth));

    final uniqueResolutions = sortedVariants.map((sv) => sv.qualityLabel).toSet();
    final isSingleResolution = uniqueResolutions.length <= 1;
    final index = sortedVariants.indexWhere((sv) => sv.url == v.url);
    final fbq = ref.read(downloadModalProvider).fallbackQuality;

    if (isSingleResolution) {
      String label;
      final reverseIndex = sortedVariants.length - 1 - index;
      if (reverseIndex == 0) {
        label = '720p';
      } else if (reverseIndex == 1) {
        label = '480p';
      } else if (reverseIndex == 2) {
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

  String _estimateSizeForResolution(String res, int? runtimeMinutes) {
    final mins = (runtimeMinutes != null && runtimeMinutes > 0) ? runtimeMinutes : 45;
    final rLower = res.toLowerCase();
    double mb;
    if (rLower.contains('2160') || rLower.contains('4k')) {
      mb = (mins * 60 * 12000000) / (8 * 1024 * 1024);
    } else if (rLower.contains('1080')) {
      mb = (mins * 60 * 4500000) / (8 * 1024 * 1024);
    } else if (rLower.contains('720')) {
      mb = (mins * 60 * 2000000) / (8 * 1024 * 1024);
    } else if (rLower.contains('480')) {
      mb = (mins * 60 * 900000) / (8 * 1024 * 1024);
    } else {
      mb = (mins * 60 * 1500000) / (8 * 1024 * 1024);
    }
    if (mb >= 1024) {
      return '~${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '~${mb.round()} MB';
  }

  Widget _buildResolutionList(DownloadModalState modalState) {
    final resolutions = modalState.availableResolutions ?? [];
    if (resolutions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.white30, size: 48),
            SizedBox(height: 16),
            Text(
              'No download resolutions available',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Please try extracting again later.',
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
        const SizedBox(height: 6),
        ...resolutions.map((res) => _buildResolutionCard(res, modalState)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildResolutionCard(String res, DownloadModalState modalState) {
    final isExtracting = modalState.extractingResolution == res;
    final exactSize = modalState.resolutionSizes?[res];
    final isExact = exactSize != null && exactSize.isNotEmpty;
    final sizeEstimate = _estimateSizeForResolution(res, modalState.runtime);
    final displaySize = isExact ? exactSize : sizeEstimate;

    // Clean label: e.g. "1080p", "720p", "480p", "4K"
    final rLower = res.toLowerCase();
    String qualityLabel;
    if (rLower.contains('2160') || rLower.contains('4k')) {
      qualityLabel = '4K';
    } else if (rLower.contains('1080')) {
      qualityLabel = '1080p';
    } else if (rLower.contains('720')) {
      qualityLabel = '720p';
    } else if (rLower.contains('480')) {
      qualityLabel = '480p';
    } else {
      qualityLabel = res;
    }

    return GestureDetector(
      onTap: isExtracting
          ? null
          : () {
              HapticFeedback.mediumImpact();
              modalState.onSelectResolution?.call(res);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isExtracting
              ? AppColors.primary.withValues(alpha: 0.12)
              : const Color(0xFF181A22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExtracting
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.08),
            width: isExtracting ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Quality (e.g. 480p, 720p, 1080p)
            Text(
              qualityLabel,
              style: GoogleFonts.outfit(
                color: isExtracting ? AppColors.primary : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            // Exact Size Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isExact
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isExact
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExact ? Icons.sd_storage_rounded : Icons.data_usage_rounded,
                    color: isExact ? AppColors.primary : Colors.white38,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    displaySize,
                    style: GoogleFonts.outfit(
                      color: isExact ? Colors.white : Colors.white60,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Action indicator (Download Icon or Progress Spinner)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isExtracting
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: isExtracting
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Center(
                child: isExtracting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_downward_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamsList(List<PeachifyStream> streams) {
    if (streams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.white30, size: 48),
            SizedBox(height: 16),
            Text(
              'No active servers available',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
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
        ...streams.map((stream) {
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
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSelectors() {
    final playlist = _playlist!;
    final filteredVariants = _getFilteredVariants(playlist, _selectedAudio);
    final sortedVariants = List<StreamVariant>.from(filteredVariants)
      ..sort((a, b) => a.bandwidth.compareTo(b.bandwidth));

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
                    Expanded(
                      child: Text(
                        fullLabel,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                onTap: () {
                  if (_selectedVariant != v) {
                    setState(() {
                      _selectedVariant = v;
                      _fetchedSizeText = 'Fetching size...';
                      _fileSizeBytes = null;
                    });
                    if (!v.url.contains('.m3u8')) {
                      _fetchActualFileSize(v.url, headers: _selectedStream?.headers);
                    }
                  }
                },
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    fileExtension: _resolvedExtension,
                    fileSizeBytes: _fileSizeBytes,
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
