// lib/quality_selector_sheet.dart
// ─────────────────────────────────────────────────────────
// Bottom sheet that shows all available qualities
// and audio tracks. User picks one combination,
// taps Download — returns their selection.
// ─────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'm3u8_parser.dart';
import 'download_manager.dart';

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
  required String m3u8Url,
  required String title,
}) async {
  // Show loading state first
  DownloadSelection? result;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QualitySelectorSheet(
      m3u8Url: m3u8Url,
      title: title,
      onSelected: (sel) {
        result = sel;
        Navigator.of(context).pop();
      },
      onCancel: () => Navigator.of(context).pop(),
    ),
  );

  return result;
}

// ══════════════════════════════════════════════════════════
//  QUALITY SELECTOR SHEET
// ══════════════════════════════════════════════════════════
class _QualitySelectorSheet extends StatefulWidget {
  final String m3u8Url;
  final String title;
  final void Function(DownloadSelection) onSelected;
  final VoidCallback onCancel;

  const _QualitySelectorSheet({
    required this.m3u8Url,
    required this.title,
    required this.onSelected,
    required this.onCancel,
  });

  @override
  State<_QualitySelectorSheet> createState() => _QualitySelectorSheetState();
}

class _QualitySelectorSheetState extends State<_QualitySelectorSheet> {
  PlaylistInfo? _playlist;
  bool _isLoading = true;
  String? _error;

  StreamVariant? _selectedVariant;
  AudioTrack? _selectedAudio;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    try {
      final parser = M3u8Parser();
      final info = await parser.parse(widget.m3u8Url);
      setState(() {
        _playlist = info;
        _selectedVariant = info.bestVariant;
        _selectedAudio = info.defaultAudio;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ───────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF30363D),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded,
                    color: Color(0xFF1F6FEB), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Color(0xFF8B949E), size: 20),
                  onPressed: widget.onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF30363D), height: 24),

          // ── Body ─────────────────────────────────────────
          if (_isLoading) _buildLoading()
          else if (_error != null) _buildError()
          else _buildSelectors(),
        ],
      ),
    );
  }

  // ── Loading state ─────────────────────────────────────
  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF1F6FEB),
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 16),
          Text(
            'Fetching available qualities...',
            style: TextStyle(
                color: Colors.white.withOpacity(0.5), fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Error state ───────────────────────────────────────
  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFD29922), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Could not parse playlist',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Fallback: download as-is
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onSelected(DownloadSelection(
                quality: StreamVariant(
                    url: widget.m3u8Url,
                    bandwidth: 0),
                audioTrack: null,
                title: widget.title,
              )),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FEB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Download anyway (auto quality)'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Main selectors ────────────────────────────────────
  Widget _buildSelectors() {
    final playlist = _playlist!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── QUALITY section ────────────────────────────
        if (playlist.variants.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.high_quality_outlined,
            label: 'Quality',
            count: playlist.variants.length,
          ),
          SizedBox(
            height: 54,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: playlist.variants.length,
              itemBuilder: (_, i) {
                final v = playlist.variants[i];
                final selected = _selectedVariant == v;
                final isBest = i == 0;
                return _QualityChip(
                  label: v.badgeLabel,
                  subLabel: v.estimatedSize,
                  selected: selected,
                  isBest: isBest,
                  onTap: () => setState(() => _selectedVariant = v),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── AUDIO TRACKS section ───────────────────────
        if (playlist.audioTracks.isNotEmpty) ...[
          const Divider(
              color: Color(0xFF30363D), height: 24, indent: 16, endIndent: 16),
          _SectionHeader(
            icon: Icons.audiotrack_outlined,
            label: 'Audio track',
            count: playlist.audioTracks.length,
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlist.audioTracks.length,
            itemBuilder: (_, i) {
              final track = playlist.audioTracks[i];
              final selected = _selectedAudio?.name == track.name &&
                  _selectedAudio?.language == track.language;
              return _AudioTrackTile(
                track: track,
                selected: selected,
                onTap: () => setState(() => _selectedAudio = track),
              );
            },
          ),
          const SizedBox(height: 8),
        ],

        // ── No options found ───────────────────────────
        if (playlist.variants.isEmpty && playlist.audioTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Single stream detected (no quality options)',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),

        const Divider(color: Color(0xFF30363D), height: 24),

        // ── Selected summary + Download button ─────────
        _buildDownloadFooter(),

        // Bottom safe area
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }

  Widget _buildDownloadFooter() {
    final variant = _selectedVariant;
    final audio = _selectedAudio;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row
          Row(
            children: [
              if (variant != null) ...[
                _SummaryBadge(
                  icon: Icons.hd_outlined,
                  label: variant.badgeLabel,
                  color: const Color(0xFF1F6FEB),
                ),
                const SizedBox(width: 8),
              ],
              if (audio != null)
                _SummaryBadge(
                  icon: Icons.audiotrack_outlined,
                  label: audio.displayName,
                  color: const Color(0xFF3FB950),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Download button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (variant != null)
                  ? () => widget.onSelected(DownloadSelection(
                        quality: variant,
                        audioTrack: audio,
                        title: widget.title,
                      ))
                  : null,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(
                variant != null
                    ? 'Download ${variant.badgeLabel}'
                        '${audio != null ? " · ${audio.name}" : ""}'
                    : 'Select a quality',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FEB),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF21262D),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quality pill chip ─────────────────────────────────────
class _QualityChip extends StatelessWidget {
  final String label;
  final String subLabel;
  final bool selected;
  final bool isBest;
  final VoidCallback onTap;

  const _QualityChip({
    required this.label,
    required this.subLabel,
    required this.selected,
    required this.isBest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1F6FEB).withOpacity(0.15)
              : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFF1F6FEB)
                : const Color(0xFF30363D),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF8B949E),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (isBest) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3FB950).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'BEST',
                      style: TextStyle(
                        color: Color(0xFF3FB950),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Text(
              subLabel,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF1F6FEB).withOpacity(0.8)
                    : const Color(0xFF484F58),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Audio track list tile ─────────────────────────────────
class _AudioTrackTile extends StatelessWidget {
  final AudioTrack track;
  final bool selected;
  final VoidCallback onTap;

  const _AudioTrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3FB950).withOpacity(0.08)
              : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFF3FB950)
                : const Color(0xFF30363D),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Flag / icon
            Text(
              track.displayName.split(' ').first, // just the flag emoji
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 12),

            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFCDD9E5),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    track.language.toUpperCase() +
                        (track.url != null ? ' · Separate track' : ' · Embedded'),
                    style: const TextStyle(
                        color: Color(0xFF8B949E), fontSize: 11),
                  ),
                ],
              ),
            ),

            // Badges
            Row(
              children: [
                if (track.isDefault)
                  _badge('DEFAULT', const Color(0xFF1F6FEB)),
                if (track.isForced)
                  _badge('FORCED', const Color(0xFFD29922)),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFF3FB950)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF3FB950)
                          : const Color(0xFF30363D),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 12)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _SectionHeader(
      {required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8B949E), size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF30363D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                  color: Color(0xFF8B949E), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary badge ─────────────────────────────────────────
class _SummaryBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SummaryBadge(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
