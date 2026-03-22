// lib/main_integration_v2.dart
// ─────────────────────────────────────────────────────────
// Updated integration:
//   WebView → detect m3u8 → parse playlist →
//   show quality+audio selector sheet →
//   download with exact ffmpeg command
// ─────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'download_manager.dart';   // use the updated v2 version
import 'downloads_screen.dart';
import 'm3u8_interceptor.dart';
import 'quality_selector_sheet.dart';

// ── After m3u8 is detected, call this ─────────────────────
// Drop this function anywhere in your app.
Future<void> handleM3u8Detected({
  required BuildContext context,
  required String m3u8Url,
  required String pageTitle,
}) async {
  // Show the quality + audio selector sheet.
  // It internally fetches and parses the master playlist.
  final selection = await showQualitySelectorSheet(
    context: context,
    m3u8Url: m3u8Url,
    title: pageTitle,
  );

  // User dismissed the sheet → do nothing
  if (selection == null || !context.mounted) return;

  // Start the download with the exact variant + audio track chosen
  final manager = DownloadManager();
  final item = await manager.startDownload(
    m3u8Url: m3u8Url,
    title: selection.title,
    variant: selection.quality,
    audioTrack: selection.audioTrack,
  );

  if (item != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1F6FEB),
        content: Row(
          children: [
            const Icon(Icons.download_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item.qualityTag.isNotEmpty ? "${item.qualityTag} · " : ""}'
                'Downloading...',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  HOME SCREEN (updated with quality selector flow)
// ══════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController(
    text: 'https://bysebuho.com/d/zldee1kirp5c/can-this-love-be-translated-s01e01-720p-nf-web-dl-dual-aac5-1-h-264-daniewatch-is',
  );

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    final activeCount = manager.downloads
        .where((d) => d.status == DownloadStatus.downloading)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Video Downloader',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.video_library_outlined, color: Colors.white),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DownloadsScreen())),
              ),
              if (activeCount > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                        color: Color(0xFF1F6FEB), shape: BoxShape.circle),
                    child: Center(
                      child: Text('$activeCount',
                          style: const TextStyle(color: Colors.white, fontSize: 9)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── URL input ──────────────────────────────
            const Text('Video page URL',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: const TextStyle(color: Color(0xFF484F58)),
                filled: true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF30363D))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF30363D))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1F6FEB))),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              maxLines: 3,
              minLines: 1,
            ),

            const SizedBox(height: 20),

            // ── Open & Detect button ───────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openInterceptor(context),
                icon: const Icon(Icons.search_rounded, size: 20),
                label: const Text('Open & Detect Stream',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6FEB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Info note ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF30363D), width: 0.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF8B949E), size: 15),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The browser will open, detect the stream URL, then ask you '
                      'to pick quality and audio track before downloading.',
                      style: TextStyle(
                          color: Color(0xFF8B949E), fontSize: 12,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            const Text('Recent downloads',
                style: TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            if (manager.downloads.isEmpty)
              const Text('No downloads yet',
                  style: TextStyle(color: Color(0xFF484F58), fontSize: 13))
            else
              ...manager.downloads.take(4).map((item) => _MiniCard(
                  item: item,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DownloadsScreen())))),
          ],
        ),
      ),
    );
  }

  void _openInterceptor(BuildContext context) {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => M3u8InterceptorView(
        pageUrl: url,
        onM3u8Detected: (m3u8Url, pageTitle) async {
          // Close the WebView first
          if (context.mounted) Navigator.of(context).pop();

          // Then show quality+audio selector and start download
          if (context.mounted) {
            await handleM3u8Detected(
              context: context,
              m3u8Url: m3u8Url,
              pageTitle: pageTitle ?? _titleFromUrl(url),
            );
          }
        },
        onClose: () => Navigator.of(context).pop(),
      ),
    ));
  }

  String _titleFromUrl(String url) {
    return Uri.parse(url).pathSegments.last
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
  }
}

// ── Mini download card ────────────────────────────────────
class _MiniCard extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onTap;
  const _MiniCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF30363D), width: 0.5),
        ),
        child: Row(
          children: [
            _dot(item.status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  if (item.qualityTag.isNotEmpty)
                    Text(item.qualityTag,
                        style: const TextStyle(
                            color: Color(0xFF8B949E), fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.status == DownloadStatus.downloading)
              SizedBox(
                width: 55,
                child: LinearProgressIndicator(
                  value: item.progress > 0 ? item.progress : null,
                  backgroundColor: const Color(0xFF30363D),
                  color: const Color(0xFF1F6FEB),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else
              Text(item.statusLabel,
                  style: TextStyle(
                    color: item.isComplete
                        ? const Color(0xFF3FB950)
                        : const Color(0xFF8B949E),
                    fontSize: 12,
                  )),
          ],
        ),
      ),
    );
  }

  Widget _dot(DownloadStatus s) {
    final colors = {
      DownloadStatus.downloading: const Color(0xFF1F6FEB),
      DownloadStatus.completed: const Color(0xFF3FB950),
      DownloadStatus.failed: const Color(0xFFFF6B6B),
      DownloadStatus.cancelled: const Color(0xFF8B949E),
      DownloadStatus.queued: const Color(0xFFD29922),
    };
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
          color: colors[s] ?? const Color(0xFF8B949E),
          shape: BoxShape.circle),
    );
  }
}
