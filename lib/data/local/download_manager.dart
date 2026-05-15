import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/router/app_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import '../../services/hls_downloader_service.dart';
import '../../services/m3u8_parser.dart';
import '../../services/download_notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../../services/background_download_service.dart';
import '../../services/video_extractor_service.dart';
import '../../services/bysebuho_extractor.dart';

/// Port name for isolate communication
const String _downloadPortName = 'downloader_send_port';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(_downloadPortName);
  send?.send([id, status, progress]);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // This callback runs in a SEPARATE background isolate.
  // Route actions to the background service isolate via IPC.
  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null) return;

  debugPrint(
      '🔔 Notification action from UI callback: $actionId for $payload');

  FlutterBackgroundService().invoke('onNotifAction', {
    'action': actionId,
    'id': payload,
  });
}

enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  canceled,
  converting
}

class DownloadItem {
  final String id;
  final String url;
  final String title;
  final int season;
  final int episode;
  final String? posterUrl;
  final String fileExtension;
  DownloadStatus status;
  double progress;
  int totalBytes;
  int downloadedBytes;
  String? localPath;
  String? taskId;
  DateTime createdAt;
  DateTime? completedAt;
  String? error;

  // ── Quality/audio/subtitle fields ──
  final String? videoStreamUrl;
  final String? audioStreamUrl;
  final String? subtitleStreamUrl;
  final String? qualityLabel;
  final String? audioLabel;
  final String? subtitleLabel;

  // ── Segment download tracking ──
  int totalSegments;
  int completedSegments;
  String? segmentDirectory;
  int downloadSpeed; // bytes per second

  // ── Resilient resume: original embed URL for re-extraction ──
  final String? originalEmbedUrl;

  // ── URL freshness tracking: when CDN URLs were obtained ──
  DateTime? urlObtainedAt;

  DownloadItem({
    required this.id,
    required this.url,
    required this.title,
    required this.season,
    required this.episode,
    this.posterUrl,
    this.fileExtension = '.mp4',
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.localPath,
    this.taskId,
    DateTime? createdAt,
    this.completedAt,
    this.error,
    this.videoStreamUrl,
    this.audioStreamUrl,
    this.subtitleStreamUrl,
    this.qualityLabel,
    this.audioLabel,
    this.subtitleLabel,
    this.totalSegments = 0,
    this.completedSegments = 0,
    this.segmentDirectory,
    this.downloadSpeed = 0,
    this.originalEmbedUrl,
    this.urlObtainedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayName {
    if (season > 0 && episode > 0) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      return 'S$s E$e $title';
    }
    return title;
  }

  /// Full filename with the original extension preserved
  String get fileName {
    final ext =
        fileExtension.startsWith('.') ? fileExtension : '.$fileExtension';
    if (season > 0 && episode > 0) {
      return '$title S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}$ext';
    }
    return '$title$ext';
  }

  /// Display tag for the download card (e.g. "720p · Hindi")
  String get qualityTag {
    final parts = <String>[];
    if (qualityLabel != null) parts.add(qualityLabel!);
    if (audioLabel != null) parts.add(audioLabel!);
    if (subtitleLabel != null) parts.add('Subtitles');
    return parts.join(' · ');
  }

  String get formattedSize {
    int bytesToFormat = totalBytes;
    bool isEstimate = false;
    if (bytesToFormat == 0 && (videoStreamUrl != null || qualityLabel != null)) {
      // Use bandwidth-based estimate (Assuming 45 min for now, as in parser)
      // We can improve this if we have a real duration later.
      // But for now, we'll use a standard estimate to satisfy the UI.
      // Note: We'll calculate it on the fly if not provided.
      bytesToFormat = _calculateEstimatedBytes();
      isEstimate = true;
    }

    if (bytesToFormat == 0) return 'Unknown';
    
    final String prefix = isEstimate ? '~' : '';
    if (bytesToFormat < 1024) return '$prefix$bytesToFormat B';
    if (bytesToFormat < 1024 * 1024) {
      return '$prefix${(bytesToFormat / 1024).toStringAsFixed(1)} KB';
    }
    if (bytesToFormat < 1024 * 1024 * 1024) {
      return '$prefix${(bytesToFormat / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '$prefix${(bytesToFormat / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int _calculateEstimatedBytes() {
    // If we have a bandwidth (from qualityLabel or similar), use it.
    // However, DownloadItem doesn't store bandwidth directly.
    // Let's assume some defaults for common labels if not available.
    if (qualityLabel != null) {
      final q = qualityLabel!.toLowerCase();
      int? bandwidth; // bits per second
      if (q.contains('1080')) bandwidth = 5000000;
      else if (q.contains('720')) bandwidth = 2500000;
      else if (q.contains('480')) bandwidth = 1500000;
      else if (q.contains('360')) bandwidth = 800000;
      
      if (bandwidth != null) {
        return (bandwidth / 8 * 45 * 60).toInt();
      }
    }
    return 0;
  }

  String get formattedProgress {
    // Show MB downloaded
    return formattedDownloadedBytes;
  }

  String get formattedDownloadedBytes {
    if (downloadedBytes == 0) return '0.0 MB';
    return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get segmentProgressLabel {
    if (totalSegments > 0) {
      final pct = (progress * 100).toInt().clamp(0, 100);
      return '$pct%';
    }
    return '';
  }

  String get formattedSpeed {
    if (downloadSpeed <= 0) return '';
    if (downloadSpeed < 1024) return '$downloadSpeed B/s';
    if (downloadSpeed < 1024 * 1024) {
      return '${(downloadSpeed / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(downloadSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get statusLabel {
    switch (status) {
      case DownloadStatus.pending:
        return 'Queued';
      case DownloadStatus.downloading:
        return '$formattedDownloadedBytes · $segmentProgressLabel';
      case DownloadStatus.completed:
        return 'Ready';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.canceled:
        return 'Cancelled';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.converting:
        return 'Converting…';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'season': season,
        'episode': episode,
        'posterUrl': posterUrl,
        'fileExtension': fileExtension,
        'status': status.index,
        'progress': progress,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'localPath': localPath,
        'taskId': taskId,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'error': error,
        'videoStreamUrl': videoStreamUrl,
        'audioStreamUrl': audioStreamUrl,
        'subtitleStreamUrl': subtitleStreamUrl,
        'qualityLabel': qualityLabel,
        'audioLabel': audioLabel,
        'subtitleLabel': subtitleLabel,
        'totalSegments': totalSegments,
        'completedSegments': completedSegments,
        'segmentDirectory': segmentDirectory,
        'downloadSpeed': downloadSpeed,
        'originalEmbedUrl': originalEmbedUrl,
        'urlObtainedAt': urlObtainedAt?.toIso8601String(),
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'],
        url: json['url'],
        title: json['title'],
        season: json['season'],
        episode: json['episode'],
        posterUrl: json['posterUrl'],
        fileExtension: json['fileExtension'] ?? '.mp4',
        status: DownloadStatus
            .values[json['status'].clamp(0, DownloadStatus.values.length - 1)],
        progress: (json['progress'] as num).toDouble(),
        totalBytes: json['totalBytes'],
        downloadedBytes: json['downloadedBytes'],
        localPath: json['localPath'],
        taskId: json['taskId'],
        createdAt: DateTime.parse(json['createdAt']),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null,
        error: json['error'],
        videoStreamUrl: json['videoStreamUrl'],
        audioStreamUrl: json['audioStreamUrl'],
        subtitleStreamUrl: json['subtitleStreamUrl'],
        qualityLabel: json['qualityLabel'],
        audioLabel: json['audioLabel'],
        subtitleLabel: json['subtitleLabel'],
        totalSegments: json['totalSegments'] ?? 0,
        completedSegments: json['completedSegments'] ?? 0,
        segmentDirectory: json['segmentDirectory'],
        downloadSpeed: json['downloadSpeed'] ?? 0,
        originalEmbedUrl: json['originalEmbedUrl'],
        urlObtainedAt: json['urlObtainedAt'] != null
            ? DateTime.tryParse(json['urlObtainedAt'])
            : null,
      );
}

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _downloadsKey = 'download_items';

  final List<DownloadItem> _downloads = [];
  final ReceivePort _port = ReceivePort();
  final Map<String, HlsDownloaderService> _activeHlsDownloads = {};
  final DownloadNotificationService _notifService =
      DownloadNotificationService();


  List<DownloadItem> get downloads => List.unmodifiable(_downloads);

  List<DownloadItem> get downloadingItems => _downloads
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.pending ||
          d.status == DownloadStatus.converting)
      .toList();

  List<DownloadItem> get completedItems =>
      _downloads.where((d) => d.status == DownloadStatus.completed).toList();

  List<DownloadItem> get failedItems =>
      _downloads.where((d) => d.status == DownloadStatus.failed).toList();

  final _updateController = StreamController<DownloadItem>.broadcast();
  Stream<DownloadItem> get updateStream => _updateController.stream;

  final _completeController = StreamController<DownloadItem>.broadcast();
  Stream<DownloadItem> get completeStream => _completeController.stream;

  @deprecated
  Function(DownloadItem)? onDownloadUpdate;
  @deprecated
  Function(DownloadItem)? onDownloadComplete;

  Future<void> initialize() async {
    if (kIsWeb) return;
    await FlutterDownloader.initialize();
    await _notifService.init(
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    
    // Initialize background service
    await BackgroundDownloadService().initialize();
    _listenToBackgroundService();
    
    await _loadDownloads();

    // Reset interrupted downloads to paused (so user can resume)
    for (var d in _downloads) {
      if (d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.converting) {
        d.status = DownloadStatus.paused;
        d.error = null;
      }
    }
    await _saveDownloads();

    // Wire notification action buttons (Pause/Resume/Cancel from notification bar)
    _notifService.onNotificationAction = (actionId, notifId, payload) {
      // Find item by payload ID (most reliable) or fallback to hashCode
      DownloadItem? item;
      if (payload != null) {
        item = _findById(payload);
      }
      item ??= _downloads.cast<DownloadItem?>().firstWhere(
            (d) => _notificationId(d!.id) == notifId,
            orElse: () => null,
          );

      if (item == null) return;

      switch (actionId) {
        case 'pause':
          pauseDownload(item.id);
          break;
        case 'resume':
          resumeDownload(item.id);
          break;
        case 'cancel':
          // Cancel directly from notification (no UI modal)
          cancelDownload(item.id);
          break;
      }
    };

    // Register the port for isolate communication (legacy flutter_downloader)
    _unbindPort();
    IsolateNameServer.registerPortWithName(_port.sendPort, _downloadPortName);

    _port.listen((dynamic data) {
      final taskId = data[0] as String;
      final status = data[1] as int;
      final progress = data[2] as int;
      _handleDownloadProgress(taskId, status, progress);
    });

    await FlutterDownloader.registerCallback(downloadCallback);
  }

  void _listenToBackgroundService() {
    final service = FlutterBackgroundService();
    
    // ── Progress updates (UI sync only, no notifications from here) ──
    service.on('progress').listen((data) {
      if (data == null) return;
      final id = data['id'];
      final item = _findById(id);
      if (item == null) return;

      // Don't override paused/cancelled status with progress from
      // segments that were already in-flight when the user tapped pause.
      if (item.status == DownloadStatus.paused ||
          item.status == DownloadStatus.canceled) {
        return;
      }

      item.progress = data['progress'] * 0.96;
      item.completedSegments = data['completed'];
      item.totalSegments = data['total'];
      item.downloadedBytes = data['bytes'];
      item.downloadSpeed = data['speed'];
      item.status = DownloadStatus.downloading;

      // Background isolate handles all notifications — no UI-side notifs here

      _updateController.add(item);
      onDownloadUpdate?.call(item);
    });

    // ── Conversion started (silent — keep showing "downloading") ──
    service.on('conversionStarted').listen((data) {
      if (data == null) return;
      final item = _findById(data['id']);
      if (item == null) return;
      
      // Keep status as downloading — conversion is silent to the user
      item.status = DownloadStatus.downloading;
      item.progress = 0.96;

      _updateController.add(item);
      onDownloadUpdate?.call(item);
    });

    // ── Download complete ──
    service.on('complete').listen((data) async {
      if (data == null) return;
      final id = data['id'];
      final path = data['path'];
      final finalizedInBg = data['finalizedInBackground'] == true;
      final item = _findById(id);
      if (item == null) return;

      if (finalizedInBg) {
        // Background isolate already moved the file and updated prefs.
        // Just update in-memory state for the UI.
        item.status = DownloadStatus.completed;
        item.progress = 1.0;
        item.completedAt = DateTime.now();
        item.localPath = path;

        _updateController.add(item);
        onDownloadComplete?.call(item);
        _completeController.add(item);
        _saveDownloads();
        _stopBackgroundServiceIfIdle();
      } else {
        // Fallback: finalize from UI isolate (shouldn't happen normally)
        await _finalizeDownload(item, path);
      }
    });

    // ── Download error ──
    service.on('error').listen((data) {
      if (data == null) return;
      final item = _findById(data['id']);
      if (item == null) return;

      item.status = DownloadStatus.failed;
      item.error = data['error'];

      // Background isolate handles the failure notification

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
      _stopBackgroundServiceIfIdle();
    });

    // ── Link Expired: CDN token expired, trigger re-extraction ──
    service.on('linkExpired').listen((data) {
      if (data == null) return;
      final id = data['id'] as String?;
      if (id == null) return;
      final item = _findById(id);
      if (item == null) return;

      debugPrint('\ud83d\udd17 Link expired for ${item.title} \u2014 attempting re-extraction');
      item.status = DownloadStatus.downloading;
      item.error = null;
      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();

      // Trigger async re-extraction
      _reExtractAndResume(item);
    });

    // ── Notification action: Pause (from background notification button) ──
    service.on('notifPause').listen((data) {
      if (data == null) return;
      final item = _findById(data['id']);
      if (item == null) return;

      item.status = DownloadStatus.paused;
      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    });

    // ── Notification action: Resume (from background notification button) ──
    service.on('notifResume').listen((data) {
      if (data == null) return;
      final item = _findById(data['id']);
      if (item == null) return;

      item.status = DownloadStatus.downloading;
      item.error = null;
      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    });

    // ── Notification action: Cancel (from background notification button) ──
    service.on('notifCancel').listen((data) {
      if (data == null) return;
      final item = _findById(data['id']);
      if (item == null) return;

      item.status = DownloadStatus.canceled;

      // Clean up segment directory
      if (item.segmentDirectory != null) {
        try {
          final segDir = Directory(item.segmentDirectory!);
          segDir.exists().then((exists) {
            if (exists) segDir.delete(recursive: true);
          });
        } catch (_) {}
      }

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
      _stopBackgroundServiceIfIdle();
    });
  }

  Future<void> _finalizeDownload(DownloadItem item, String tempPath) async {
    try {
      final String safeFileName = item.fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      
      // Destination: root Download folder (no subfolder)
      final String finalPath = '/storage/emulated/0/Download/$safeFileName';
      
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        throw Exception('Muxed file not found at $tempPath');
      }

      // Copy to public Downloads, then delete the temp file
      await tempFile.copy(finalPath);

      // Verify the copy landed
      final destFile = File(finalPath);
      if (!await destFile.exists()) {
        throw Exception('File copy to Downloads failed');
      }

      item.status = DownloadStatus.completed;
      item.progress = 1.0;
      item.completedAt = DateTime.now();
      item.localPath = finalPath;

      // Cleanup: Remove temp muxed file
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) {
        debugPrint('Cleanup error (temp file): $e');
      }

      // Cleanup: Remove segment directory
      if (item.segmentDirectory != null) {
        try {
          final segDir = Directory(item.segmentDirectory!);
          if (await segDir.exists()) await segDir.delete(recursive: true);
        } catch (e) {
          debugPrint('Cleanup error (segments): $e');
        }
      }
      
      // Background isolate handles completion notification
      // No need to show notification from UI isolate
    } catch (e) {
      debugPrint('Finalization error: $e');
      item.status = DownloadStatus.failed;
      item.error = 'Failed to save file. Please check your storage.';
    }

    _updateController.add(item);
    onDownloadComplete?.call(item);
    _saveDownloads();
  }

  void _unbindPort() {
    IsolateNameServer.removePortNameMapping(_downloadPortName);
  }

  void _handleDownloadProgress(String taskId, int status, int progress) {
    final item = _findByTaskId(taskId);
    if (item == null) {
      debugPrint('Download item not found for taskId: $taskId');
      return;
    }

    item.progress = progress / 100.0;
    item.downloadedBytes = (item.totalBytes * item.progress).toInt();

    if (status == DownloadTaskStatus.complete.index) {
      item.status = DownloadStatus.completed;
      item.completedAt = DateTime.now();
      _notifService.showComplete(
          id: _notificationId(item.id), title: 'Download Completed', body: item.displayName, payload: item.id);
      onDownloadComplete?.call(item);
    } else if (status == DownloadTaskStatus.failed.index) {
      item.status = DownloadStatus.failed;
      item.error = 'Download failed';
      _notifService.showFailed(
          id: _notificationId(item.id), title: 'Download Failed', error: item.displayName, payload: item.id);
    } else if (status == DownloadTaskStatus.canceled.index) {
      item.status = DownloadStatus.canceled;
    } else if (status == DownloadTaskStatus.running.index) {
      item.status = DownloadStatus.downloading;
    } else if (status == DownloadTaskStatus.paused.index) {
      item.status = DownloadStatus.paused;
    }

    _updateController.add(item);
    onDownloadUpdate?.call(item);
    _saveDownloads();
  }

  DownloadItem? _findByTaskId(String taskId) {
    for (final d in _downloads) {
      if (d.taskId == taskId) return d;
    }
    return null;
  }

  static String extractExtension(String url) {
    try {
      String path = url.split('?').first.split('#').first;
      final lastSegment = path.split('/').last;
      final dotIndex = lastSegment.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < lastSegment.length - 1) {
        final ext = lastSegment.substring(dotIndex).toLowerCase();
        const validExts = [
          '.mp4',
          '.mkv',
          '.avi',
          '.mov',
          '.wmv',
          '.flv',
          '.webm',
          '.m4v',
          '.ts',
          '.m3u8'
        ];
        if (validExts.contains(ext)) {
          return ext;
        }
      }
    } catch (_) {}
    return '.mp4';
  }

  Future<bool> requestPermissions([BuildContext? context]) async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // 1. Notification Permission (All versions Android 13+)
      if (sdkInt >= 33) {
        await Permission.notification.request();
      }

      // 2. Storage/Media Permission
      PermissionStatus status;
      if (sdkInt >= 33) {
        // Android 13+ Granular Permissions
        // We primarily need videos for this app
        final statuses = await [
          Permission.videos,
          Permission.photos,
        ].request();
        
        status = statuses[Permission.videos] ?? PermissionStatus.denied;
      } else {
        // Android 12 and below
        status = await Permission.storage.request();
      }

      // 3. Optional: Request Manage External Storage for Android 11+ if standard fails
      if (sdkInt >= 30) {
        final manageStatus = await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
           // We'll prompt the user if they want better reliability
           // But for now just request it if we really need it
        }
      }
      
      if (status.isPermanentlyDenied) {
        _showPermissionSettingsDialog(context);
        return false;
      }
      
      // If we are on Android 11+ and don't have manage storage, 
      // we can still proceed with MediaStore, but it might be less reliable for FFmpeg.
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  Future<void> requestManageStorage([BuildContext? context]) async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        if (await Permission.manageExternalStorage.isGranted) return;
        
        final ctx = context ?? AppRouter.rootNavKey.currentContext;
        if (ctx != null) {
          final proceed = await showDialog<bool>(
            context: ctx,
            builder: (context) => AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              title: const Text('Full Storage Access', style: TextStyle(color: Colors.white)),
              content: const Text(
                'For 100% reliable background downloads on your Android version, DanieWatch needs "All Files Access". This prevents downloads from failing during video processing.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Skip')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );
          
          if (proceed == true) {
            await Permission.manageExternalStorage.request();
          }
        }
      }
    }
  }

  void _showPermissionSettingsDialog(BuildContext? providedContext) {
    final context = providedContext ?? AppRouter.rootNavKey.currentContext;
    if (context == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Permissions Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Storage and Notification permissions are required to download files. Please enable them in app settings.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<Directory> getDownloadDirectory() async {
    if (kIsWeb) throw UnsupportedError('Downloads not supported on web');
    if (Platform.isAndroid) {
      // Use the device's public Download folder so files are visible in
      // file manager and persist even after app uninstall.
      // Path: /storage/emulated/0/Download
      final publicDownload = Directory('/storage/emulated/0/Download');
      try {
        if (!await publicDownload.exists()) {
          await publicDownload.create(recursive: true);
        }
        return publicDownload;
      } catch (_) {
        // Fallback: try getExternalStorageDirectory if public path fails
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dir = Directory(extDir.path);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      }
      // Final fallback to app documents directory
      return await getApplicationDocumentsDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  // ═══════════════════════════════════════════════════════════
  //  SEGMENT-BASED HLS DOWNLOAD (PRIMARY METHOD)
  // ═══════════════════════════════════════════════════════════

  /// Start a segment-based HLS download with quality selection.
  /// Downloads .ts segments in parallel, then converts to .mp4.
  Future<DownloadItem?> startSegmentDownload({
    required String m3u8Url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
    StreamVariant? variant,
    AudioTrack? audioTrack,
    SubtitleTrack? subtitleTrack,
    BuildContext? context,
    String? originalEmbedUrl,
  }) async {
    final hasPermission = await requestPermissions(context);
    if (!hasPermission) return null;

    final qualityLbl = variant?.badgeLabel;
    final audioLbl = audioTrack?.displayName;
    final subLbl = subtitleTrack?.name;
    final videoUrl = variant?.url ?? m3u8Url;
    final audioUrl = audioTrack?.url;
    final subtitleUrl = subtitleTrack?.url;

    // Use internal cache for segments to avoid permission/Scoped Storage issues
    final tempDir = await getTemporaryDirectory();
    final publicDir = await getDownloadDirectory();
    
    final safeTitle = _buildSafeTitle(title, season, episode, qualityLbl);
    final ts = DateTime.now().millisecondsSinceEpoch;
    
    // Internal paths for working
    final tempMp4Path = '${tempDir.path}/${safeTitle}_$ts.mp4';
    final segmentDir = '${tempDir.path}/.segments_${safeTitle}_$ts';
    
    // Public path for the final destination
    final publicMp4Path = '${publicDir.path}/$safeTitle.mp4';

    final item = DownloadItem(
      id: ts.toString(),
      url: m3u8Url,
      title: title,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      fileExtension: '.mp4',
      status: DownloadStatus.downloading,
      videoStreamUrl: videoUrl,
      audioStreamUrl: audioUrl,
      subtitleStreamUrl: subtitleUrl,
      qualityLabel: qualityLbl,
      audioLabel: audioLbl,
      subtitleLabel: subLbl,
      localPath: publicMp4Path, // The user-visible path
      segmentDirectory: segmentDir,
      totalBytes: variant != null ? (variant.bandwidth / 8 * 45 * 60).toInt() : 0,
      originalEmbedUrl: originalEmbedUrl,
      urlObtainedAt: DateTime.now(),
    );

    // Store the internal path temporarily to handle the move later
    // We'll use a local variable in _runSegmentDownload for the service call

    _downloads.insert(0, item);
    await _saveDownloads();
    _updateController.add(item);
    onDownloadUpdate?.call(item);

    // Background isolate handles all notifications and file finalization

    await BackgroundDownloadService().startDownload(
      id: item.id,
      title: item.displayName,
      videoUrl: item.videoStreamUrl ?? item.url,
      audioUrl: item.audioStreamUrl,
      subtitleUrl: item.subtitleStreamUrl,
      saveDir: segmentDir,
      outputMp4Path: tempMp4Path,
      fileName: item.fileName,
    );
    
    return item;
  }

  String _buildSafeTitle(
      String title, int season, int episode, String? quality) {
    final parts = <String>[title];
    if (season > 0 && episode > 0) {
      parts.add(
          'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}');
    }
    if (quality != null) parts.add(quality.replaceAll(' ', ''));
    String result = parts.join('_').replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_');
    if (result.length > 80) result = result.substring(0, 80);
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  //  PAUSE / RESUME / CANCEL / DELETE
  // ═══════════════════════════════════════════════════════════

  /// Pause a running download
  Future<void> pauseDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    // Background Service
    item.status = DownloadStatus.paused;
    BackgroundDownloadService().pauseDownload(id);

    // Legacy flutter_downloader
    if (item.taskId != null) {
      await FlutterDownloader.pause(taskId: item.taskId!);
    }

    _saveDownloads();
    _updateController.add(item);
    onDownloadUpdate?.call(item);
  }

  /// Play whatever segments have been downloaded so far.
  /// Pauses the download, creates a temporary preview MP4, and returns the path.
  /// Returns null if not enough segments are available.
  Future<String?> playPartialDownload(String id) async {
    final item = _findById(id);
    if (item == null || item.segmentDirectory == null) return null;

    // Must have at least some progress
    if (item.completedSegments < 2) return null;

    // Pause the download first
    if (item.status == DownloadStatus.downloading) {
      await pauseDownload(id);
      // Small delay to let in-flight segments finish writing
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Clean up any previous preview file
    final tempDir = await getTemporaryDirectory();
    final existingPreviews = await tempDir
        .list()
        .where((e) => e is File && e.path.endsWith('_preview.mp4'))
        .toList();
    for (final preview in existingPreviews) {
      try { await preview.delete(); } catch (_) {}
    }

    // Mux the available segments
    final previewPath = await HlsDownloaderService.muxPartialSegments(
      segmentDirectory: item.segmentDirectory!,
      outputDir: tempDir.path,
      title: item.displayName,
    );

    return previewPath;
  }

  /// Resume a paused download
  ///
  /// If the background service is still alive, we simply flip the pause flag.
  /// If the service was killed by the OS while paused, we restart the download
  /// from scratch — the HLS downloader automatically skips segments that are
  /// already on disk, so this effectively resumes from where it left off.
  Future<void> resumeDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    item.status = DownloadStatus.downloading;
    item.error = null;
    _updateController.add(item);
    _saveDownloads();

    // ── Smart Resume: Check if CDN URLs are likely expired ──
    // CDN tokens typically expire after 2-3 hours.
    // If URLs are older than 90 minutes, proactively re-extract.
    final urlAge = item.urlObtainedAt != null
        ? DateTime.now().difference(item.urlObtainedAt!)
        : const Duration(hours: 99); // Assume expired if no timestamp

    if (urlAge.inMinutes > 90 && item.originalEmbedUrl != null && item.originalEmbedUrl!.isNotEmpty) {
      debugPrint('🔗 URLs are ${urlAge.inMinutes}min old (>90min) — triggering re-extraction for ${item.title}');
      await _reExtractAndResume(item);
      return;
    }

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (isRunning) {
      // Fast path: service still alive, downloader instance exists
      BackgroundDownloadService().resumeDownload(id);
    } else {
      // Service was killed — restart the download from scratch.
      // Already-downloaded segments are skipped automatically.
      debugPrint('⚠ Service not running on resume — restarting download for $id');
      if (item.segmentDirectory != null) {
        // Derive the temp mp4 path from the segment directory
        // segmentDir = <tmpDir>/.segments_<safeTitle>_<ts>
        // tempMp4    = <tmpDir>/<safeTitle>_<ts>.mp4
        final segDirName = item.segmentDirectory!.split('/').last;
        final baseName = segDirName.replaceFirst('.segments_', '');
        final parentDir = item.segmentDirectory!.substring(
            0, item.segmentDirectory!.length - segDirName.length - 1);
        final tempMp4Path = '$parentDir/$baseName.mp4';

        await BackgroundDownloadService().startDownload(
          id: item.id,
          title: item.displayName,
          videoUrl: item.videoStreamUrl ?? item.url,
          audioUrl: item.audioStreamUrl,
          subtitleUrl: item.subtitleStreamUrl,
          saveDir: item.segmentDirectory!,
          outputMp4Path: tempMp4Path,
          fileName: item.fileName,
        );
      }
    }
    
    // Foreground service notification handles resuming status

    // Legacy flutter_downloader
    if (item.taskId != null) {
      final taskId = await FlutterDownloader.resume(taskId: item.taskId!);
      item.taskId = taskId;
    }

    _saveDownloads();
    _updateController.add(item);
    onDownloadUpdate?.call(item);
  }

  /// Cancel a running download
  Future<void> cancelDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    item.status = DownloadStatus.canceled;
    
    // Background Service
    BackgroundDownloadService().cancelDownload(id);
    
    // Legacy flutter_downloader
    if (item.taskId != null) {
      await FlutterDownloader.cancel(taskId: item.taskId!);
    }

    // Foreground service notification is dismissed by _stopBackgroundServiceIfIdle

    // Clean up segment directory if exists
    if (item.segmentDirectory != null) {
      try {
        final segDir = Directory(item.segmentDirectory!);
        if (await segDir.exists()) await segDir.delete(recursive: true);
      } catch (_) {}
    }

    _saveDownloads();
    _updateController.add(item);
    onDownloadUpdate?.call(item);
    
    // Stop the background service + foreground notification if no more active downloads
    _stopBackgroundServiceIfIdle();
  }

  /// Delete a download item and optionally its file
  Future<void> deleteDownload(String id, {bool deleteFile = true}) async {
    final item = _findById(id);
    if (item == null) return;

    // Cancel if still active (this also cancels notifications & stops service)
    await cancelDownload(id);

    // Cancel any lingering completion/failure notification
    _notifService.cancel(_notificationId(id));

    if (deleteFile) {
      // Delete the output file
      if (item.localPath != null && !kIsWeb) {
        final file = File(item.localPath!);
        if (await file.exists()) await file.delete();
      }
    }

    _downloads.removeWhere((d) => d.id == id);
    _saveDownloads();
  }

  // ═══════════════════════════════════════════════════════════
  //  LEGACY DOWNLOAD METHOD (direct MP4 URLs via flutter_downloader)
  // ═══════════════════════════════════════════════════════════

  Future<DownloadItem> startDownload({
    required String url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
    BuildContext? context,
  }) async {
    if (kIsWeb) throw UnsupportedError('Downloads are not supported on web.');
    final hasPermission = await requestPermissions(context);
    if (!hasPermission) {
      throw Exception('Storage permission denied');
    }

    final ext = extractExtension(url);

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      title: title,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      fileExtension: ext,
      status: DownloadStatus.downloading,
    );

    _downloads.insert(0, item);
    _saveDownloads();

    try {
      final dir = await getDownloadDirectory();
      final fileName = item.fileName;

      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        fileName: fileName,
        showNotification: true,
        saveInPublicStorage: true,
      );

      item.taskId = taskId;
      item.localPath = '${dir.path}/$fileName';
      _saveDownloads();

      onDownloadUpdate?.call(item);
    } catch (e) {
      item.status = DownloadStatus.failed;
      item.error = 'Download failed. Please try again.';
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }

    return item;
  }

  Future<void> clearCompleted() async {
    _downloads.removeWhere((d) => d.status == DownloadStatus.completed);
    _saveDownloads();
  }

  DownloadItem? _findById(String id) {
    for (final d in _downloads) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Generate a collision-resistant notification ID from the download item ID.
  static int _notificationId(String itemId) {
    final ts = int.tryParse(itemId) ?? itemId.hashCode;
    return ts.abs() % 2147483647;
  }

  /// The foreground service notification ID used by flutter_background_service.
  /// Must match the value in BackgroundDownloadService.initialize().
  static const int _foregroundServiceNotifId = 888;

  /// Stop the background service and dismiss the foreground notification
  /// if there are no more active (downloading/pending/converting) downloads.
  void _stopBackgroundServiceIfIdle() {
    final hasActive = _downloads.any((d) =>
        d.status == DownloadStatus.downloading ||
        d.status == DownloadStatus.pending ||
        d.status == DownloadStatus.converting);

    if (!hasActive) {
      debugPrint('🛑 No active downloads — stopping background service');
      // Stop the background service (which dismisses its own foreground notif)
      FlutterBackgroundService().invoke('stopService');
      // Also explicitly cancel the foreground service notification in case
      // stopSelf() doesn't dismiss it immediately on some OEMs
      _notifService.cancel(_foregroundServiceNotifId);
    }
  }

  Future<void> _loadDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_downloadsKey);
      if (data != null) {
        final List<dynamic> jsonList = jsonDecode(data);
        _downloads.clear();
        _downloads.addAll(jsonList.map((json) => DownloadItem.fromJson(json)));
      }
    } catch (e) {
      debugPrint('Error loading downloads: $e');
    }
  }

  Future<void> _saveDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_downloads.map((d) => d.toJson()).toList());
      await prefs.setString(_downloadsKey, data);
    } catch (e) {
      debugPrint('Error saving downloads: $e');
    }
  }

  DownloadItem? getDownloadByUrl(String url) {
    for (final d in _downloads) {
      if (d.url == url) return d;
    }
    return null;
  }

  // ─── Delete Confirmation Modal (trigger from Notification) ────────────────
  void _showDeleteConfirmationGlobal(DownloadItem item) {
    final context = AppRouter.rootNavKey.currentContext;
    if (context == null) {
      cancelDownload(item.id);
      return;
    }

    bool deleteFromStorage = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Delete Confirmation',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Delete Download?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Are you sure you want to delete\n"${item.displayName}"?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            deleteFromStorage = !deleteFromStorage;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: deleteFromStorage
                                  ? Colors.red.withValues(alpha: 0.4)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                deleteFromStorage
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: deleteFromStorage
                                    ? Colors.red
                                    : AppColors.textMuted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Also delete from device storage',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side:
                                      const BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                deleteDownload(
                                  item.id,
                                  deleteFile: deleteFromStorage,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  RE-EXTRACTION & RESILIENT RESUME
  // ═══════════════════════════════════════════════════════════

  /// Triggered when CDN links expire during download.
  /// Re-extracts a fresh stream URL from the saved embed URL,
  /// cleans corrupted partial segments, and restarts the download.
  Future<void> _reExtractAndResume(DownloadItem item) async {
    if (item.originalEmbedUrl == null || item.originalEmbedUrl!.isEmpty) {
      debugPrint('⚠ No originalEmbedUrl saved — cannot re-extract for ${item.title}');
      item.status = DownloadStatus.failed;
      item.error = 'Link expired. No embed URL saved for recovery.';
      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
      return;
    }

    debugPrint('🔄 Re-extracting from: ${item.originalEmbedUrl}');

    try {
      // Phase 0: Clear ALL cached URLs for this embed to force truly fresh extraction
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('extract_${item.originalEmbedUrl}');
      // Clear Bysebuho-specific cache if applicable
      final bysebuho = BysebuhoExtractor.instance;
      if (bysebuho.isBysebuhoUrl(item.originalEmbedUrl!)) {
        final code = bysebuho.extractCode(item.originalEmbedUrl!);
        if (code != null) {
          await prefs.remove('bysebuho_$code');
          debugPrint('🧹 Cleared Bysebuho cache for code: $code');
        }
      }
      debugPrint('🧹 Cleared extraction cache for: ${item.originalEmbedUrl}');

      // Phase 1: Extract fresh master M3U8 URL
      final extractor = VideoExtractorService();

      String? freshM3u8 = await extractor.extractVideoUrl(
        item.originalEmbedUrl!,
        bypassCache: true,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );

      // Retry once if first attempt fails
      if (freshM3u8 == null || freshM3u8.isEmpty) {
        debugPrint('🔄 First re-extraction failed, retrying...');
        await Future.delayed(const Duration(seconds: 2));
        freshM3u8 = await extractor.extractVideoUrl(
          item.originalEmbedUrl!,
          bypassCache: true,
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () => null,
        );
      }

      if (freshM3u8 == null || freshM3u8.isEmpty) {
        debugPrint('❌ Re-extraction failed for ${item.title}');
        item.status = DownloadStatus.failed;
        item.error = 'Re-extraction failed. Try again later.';
        _updateController.add(item);
        onDownloadUpdate?.call(item);
        _saveDownloads();
        return;
      }

      debugPrint('✅ Got fresh M3U8: $freshM3u8');

      // Phase 2: Parse fresh master playlist to find matching quality
      String? freshVideoUrl;
      String? freshAudioUrl;
      String? freshSubtitleUrl;

      try {
        final parser = M3u8Parser();
        final masterData = await parser.parse(freshM3u8);

        // Match by qualityLabel
        if (item.qualityLabel != null && masterData.variants.isNotEmpty) {
          final match = masterData.variants.cast<StreamVariant?>().firstWhere(
            (v) => v!.qualityLabel == item.qualityLabel,
            orElse: () => null,
          );
          if (match != null) {
            freshVideoUrl = match.url;
            debugPrint('✅ Matched quality: ${item.qualityLabel} → ${match.url}');
          } else {
            // Fallback: use first variant
            freshVideoUrl = masterData.variants.first.url;
            debugPrint('⚠ Quality label not found, using first: ${masterData.variants.first.qualityLabel}');
          }
        } else if (masterData.variants.isNotEmpty) {
          freshVideoUrl = masterData.variants.first.url;
        }

        // Match audio track by name
        if (item.audioLabel != null && masterData.audioTracks.isNotEmpty) {
          final audioMatch = masterData.audioTracks.cast<AudioTrack?>().firstWhere(
            (a) => a!.name == item.audioLabel || a.displayName == item.audioLabel,
            orElse: () => null,
          );
          if (audioMatch != null) {
            freshAudioUrl = audioMatch.url;
            debugPrint('✅ Matched audio: ${item.audioLabel}');
          } else if (masterData.audioTracks.isNotEmpty) {
            freshAudioUrl = masterData.audioTracks.first.url;
          }
        }

        // Match subtitle track by name
        if (item.subtitleLabel != null && masterData.subtitles.isNotEmpty) {
          final subMatch = masterData.subtitles.cast<SubtitleTrack?>().firstWhere(
            (s) => s!.name == item.subtitleLabel,
            orElse: () => null,
          );
          if (subMatch != null) {
            freshSubtitleUrl = subMatch.url;
          }
        }
      } catch (e) {
        debugPrint('⚠ Master playlist parsing failed, using raw M3U8 as video URL: $e');
        freshVideoUrl = freshM3u8;
      }

      freshVideoUrl ??= freshM3u8;

      // Phase 3: Clean corrupted partial segments
      if (item.segmentDirectory != null) {
        await _cleanCorruptedSegments(item.segmentDirectory!);
      }

      // Phase 4: Restart download with fresh URLs
      debugPrint('🚀 Restarting download with fresh URLs for ${item.title}');
      item.status = DownloadStatus.downloading;
      item.error = null;
      item.urlObtainedAt = DateTime.now(); // Track fresh URL timestamp

      if (item.segmentDirectory != null) {
        final segDirName = item.segmentDirectory!.split('/').last;
        final baseName = segDirName.replaceFirst('.segments_', '');
        final parentDir = item.segmentDirectory!.substring(
            0, item.segmentDirectory!.length - segDirName.length - 1);
        final tempMp4Path = '$parentDir/$baseName.mp4';

        await BackgroundDownloadService().startDownload(
          id: item.id,
          title: item.displayName,
          videoUrl: freshVideoUrl,
          audioUrl: freshAudioUrl,
          subtitleUrl: freshSubtitleUrl,
          saveDir: item.segmentDirectory!,
          outputMp4Path: tempMp4Path,
          fileName: item.fileName,
        );
      }

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    } catch (e) {
      debugPrint('❌ Re-extraction error: $e');
      item.status = DownloadStatus.failed;
      item.error = 'Download link expired. Tap \u25b6 to retry.';
      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    }
  }

  /// Delete corrupted/partial segment files that may have been
  /// partially written when the download was interrupted.
  Future<void> _cleanCorruptedSegments(String segmentDir) async {
    try {
      final dir = Directory(segmentDir);
      if (!await dir.exists()) return;

      final files = await dir.list().toList();
      files.sort((a, b) => a.path.compareTo(b.path));

      int cleaned = 0;
      for (final entity in files) {
        if (entity is! File) continue;
        final file = entity;
        final size = await file.length();

        // Delete files that are suspiciously small (likely corrupted)
        // A valid segment is typically > 1KB
        if (size > 0 && size < 1024) {
          debugPrint('🧹 Deleting corrupted segment: ${p.basename(file.path)} (${size}B)');
          await file.delete();
          cleaned++;
        }
      }

      if (cleaned > 0) {
        debugPrint('🧹 Cleaned $cleaned corrupted segments');
      }
    } catch (e) {
      debugPrint('⚠ Segment cleanup error: $e');
    }
  }
}
