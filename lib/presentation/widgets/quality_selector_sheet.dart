// lib/presentation/widgets/quality_selector_sheet.dart
// ─────────────────────────────────────────────────────────
// Bottom sheet that shows all available qualities
// and audio tracks. User picks one combination,
// taps Download — returns their selection.
// ─────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/m3u8_parser.dart';
import '../providers/download_modal_provider.dart';

// ── What the user selected ────────────────────────────────
class DownloadSelection {
  final StreamVariant quality;
  final AudioTrack? audioTrack;
  final String title;

  DownloadSelection({
    required this.quality,
    required this.audioTrack,
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
}) async {
  final completer = Completer<DownloadSelection?>();

  ref.read(downloadModalProvider.notifier).state = DownloadModalState(
    isOpen: true,
    isLoading: isLoading,
    m3u8Url: m3u8Url,
    title: title,
    season: season,
    episode: episode,
    onSelected: (sel) {
      ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
      if (!completer.isCompleted) completer.complete(sel);
    },
    onCancel: () {
      ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  return completer.future;
}

// ══════════════════════════════════════════════════════════
//  QUALITY SELECTOR CONTENT
// ══════════════════════════════════════════════════════════
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
  ConsumerState<QualitySelectorContent> createState() => _QualitySelectorContentState();
}

class _QualitySelectorContentState extends ConsumerState<QualitySelectorContent> {
  PlaylistInfo? _playlist;
  bool _internalLoading = true;
  String? _error;

  StreamVariant? _selectedVariant;
  AudioTrack? _selectedAudio;

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
          _selectedVariant = info.bestVariant;
          _selectedAudio = info.defaultAudio;
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

  String _getAudioDisplayName(AudioTrack track) {
    final name = track.name.toLowerCase();
    final lang = track.language.toLowerCase();
    
    if (name.contains('hindi') || lang == 'hi') return '🇮🇳 Hindi';
    if (name.contains('english') || lang == 'en') return '🇺🇸 English';
    if (name.contains('japanese') || lang == 'ja') return '🇯🇵 Japanese';
    if (name.contains('korean') || lang == 'ko') return '🇰🇷 Korean';
    if (name.contains('tamil') || lang == 'ta') return '🇮🇳 Tamil';
    if (name.contains('telugu') || lang == 'te') return '🇮🇳 Telugu';
    if (name.contains('french') || lang == 'fr') return '🇫🇷 French';
    if (name.contains('spanish') || lang == 'es') return '🇪🇸 Spanish';
    
    return '🌐 ${track.name}';
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
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download_rounded, color: Colors.red, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (modalState.season != null && modalState.episode != null && modalState.season! > 0)
                        Text(
                          'SEASON ${modalState.season} · EPISODE ${modalState.episode}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                  onPressed: widget.onCancel,
                ),
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
      baseColor: Colors.white.withOpacity(0.05),
      highlightColor: Colors.white.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          children: [
            Row(
              children: List.generate(3, (i) => Container(
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
            ...List.generate(2, (i) => Container(
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
          const Text('Extraction failed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_error ?? 'Unknown error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onSelected(DownloadSelection(
                quality: StreamVariant(url: widget.m3u8Url, bandwidth: 0),
                audioTrack: null,
                title: widget.title,
              )),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Download Original'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectors() {
    final playlist = _playlist!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quality
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('SELECT QUALITY', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playlist.variants.length,
            itemBuilder: (_, i) {
              final v = playlist.variants[i];
              final isSelected = _selectedVariant == v;
              return GestureDetector(
                onTap: () => setState(() => _selectedVariant = v),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.red : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? Colors.red : Colors.white10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    v.badgeLabel.replaceAll(' HD', '').replaceAll('SD', 'Original'),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
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
            child: Text('AUDIO TRACK', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          ...playlist.audioTracks.map((track) {
            final isSelected = _selectedAudio == track;
            return GestureDetector(
              onTap: () => setState(() => _selectedAudio = track),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? Colors.red : Colors.white10),
                ),
                child: Row(
                  children: [
                    Text(_getAudioDisplayName(track), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (isSelected) const Icon(Icons.check_circle, color: Colors.red, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildDownloadButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _selectedVariant != null ? () {
            widget.onSelected(DownloadSelection(
              quality: _selectedVariant!,
              audioTrack: _selectedAudio,
              title: widget.title,
            ));
          } : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: const Text('Start Download', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}


