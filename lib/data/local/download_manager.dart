import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../services/hls_downloader_service.dart';

/// Port name for isolate communication
const String _downloadPortName = 'downloader_send_port';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  // Send data from isolate to main isolate via IsolateNameServer
  final SendPort? send = IsolateNameServer.lookupPortByName(_downloadPortName);
  send?.send([id, status, progress]);
}

enum DownloadStatus { pending, downloading, paused, completed, failed, canceled }

class DownloadItem {
  final String id;
  final String url;
  final String title;
  final int season;
  final int episode;
  final String? posterUrl;
  final String fileExtension; // Preserved from original URL
  DownloadStatus status;
  double progress;
  int totalBytes;
  int downloadedBytes;
  String? localPath;
  String? taskId;
  DateTime createdAt;
  DateTime? completedAt;
  String? error;

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
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayName {
    if (season > 0 && episode > 0) {
      return '$title S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}';
    }
    return title;
  }

  /// Full filename with the original extension preserved
  String get fileName {
    final ext = fileExtension.startsWith('.') ? fileExtension : '.$fileExtension';
    if (season > 0 && episode > 0) {
      return '$title S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}$ext';
    }
    return '$title$ext';
  }

  String get formattedSize {
    if (totalBytes == 0) return 'Unknown';
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedProgress {
    return '${(progress * 100).toStringAsFixed(0)}%';
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
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
    id: json['id'],
    url: json['url'],
    title: json['title'],
    season: json['season'],
    episode: json['episode'],
    posterUrl: json['posterUrl'],
    fileExtension: json['fileExtension'] ?? '.mp4',
    status: DownloadStatus.values[json['status']],
    progress: (json['progress'] as num).toDouble(),
    totalBytes: json['totalBytes'],
    downloadedBytes: json['downloadedBytes'],
    localPath: json['localPath'],
    taskId: json['taskId'],
    createdAt: DateTime.parse(json['createdAt']),
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    error: json['error'],
  );
}

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _downloadsKey = 'download_items';
  
  final List<DownloadItem> _downloads = [];
  final ReceivePort _port = ReceivePort();
  final Map<String, HlsDownloaderService> _activeHlsDownloads = {};
  
  List<DownloadItem> get downloads => List.unmodifiable(_downloads);
  
  List<DownloadItem> get downloadingItems => 
      _downloads.where((d) => d.status == DownloadStatus.downloading || d.status == DownloadStatus.pending).toList();
  
  List<DownloadItem> get completedItems => 
      _downloads.where((d) => d.status == DownloadStatus.completed).toList();
  
  List<DownloadItem> get failedItems => 
      _downloads.where((d) => d.status == DownloadStatus.failed).toList();

  Function(DownloadItem)? onDownloadUpdate;
  Function(DownloadItem)? onDownloadComplete;

  Future<void> initialize() async {
    if (kIsWeb) return;
    await FlutterDownloader.initialize();
    await _loadDownloads();
    
    // Auto-pause any HLS downloads that were interrupted
    for (var d in _downloads) {
      if (d.fileExtension == '.m3u8' && d.status == DownloadStatus.downloading) {
        d.status = DownloadStatus.paused;
      }
    }
    await _saveDownloads();
    
    // Register the port for isolate communication
    _unbindPort(); // Clean up any previous binding
    IsolateNameServer.registerPortWithName(_port.sendPort, _downloadPortName);
    
    // Listen for download progress from the isolate callback
    _port.listen((dynamic data) {
      final taskId = data[0] as String;
      final status = data[1] as int;
      final progress = data[2] as int;
      _handleDownloadProgress(taskId, status, progress);
    });
    
    await FlutterDownloader.registerCallback(downloadCallback);
  }

  void _unbindPort() {
    IsolateNameServer.removePortNameMapping(_downloadPortName);
  }

  void _handleDownloadProgress(String taskId, int status, int progress) {
    // Use safe lookup instead of firstWhere that throws
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
      onDownloadComplete?.call(item);
    } else if (status == DownloadTaskStatus.failed.index) {
      item.status = DownloadStatus.failed;
      item.error = 'Download failed';
    } else if (status == DownloadTaskStatus.canceled.index) {
      item.status = DownloadStatus.canceled;
    } else if (status == DownloadTaskStatus.running.index) {
      item.status = DownloadStatus.downloading;
    } else if (status == DownloadTaskStatus.paused.index) {
      item.status = DownloadStatus.paused;
    }
    
    onDownloadUpdate?.call(item);
    _saveDownloads();
  }

  /// Safely find a download item by its taskId
  DownloadItem? _findByTaskId(String taskId) {
    for (final d in _downloads) {
      if (d.taskId == taskId) return d;
    }
    return null;
  }

  /// Extract file extension from a URL, preserving the original format
  static String extractExtension(String url) {
    try {
      // Remove query parameters and fragments
      String path = url.split('?').first.split('#').first;
      // Get the last path segment
      final lastSegment = path.split('/').last;
      // Find the extension
      final dotIndex = lastSegment.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < lastSegment.length - 1) {
        final ext = lastSegment.substring(dotIndex).toLowerCase();
        // Validate it's a known video extension
        const validExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.ts', '.m3u8'];
        if (validExts.contains(ext)) {
          return ext;
        }
      }
    } catch (_) {}
    return '.mp4'; // Default fallback
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        final manageStatus = await Permission.manageExternalStorage.request();
        return manageStatus.isGranted;
      }
      return status.isGranted;
    }
    return true;
  }

  Future<Directory> getDownloadDirectory() async {
    if (kIsWeb) throw UnsupportedError('Downloads not supported on web');
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download/DanieWatch');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<DownloadItem> startDownload({
    required String url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
  }) async {
    if (kIsWeb) throw UnsupportedError('Downloads are not supported on web.');
    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Storage permission denied');
    }

    // Extract the real file extension from the URL
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
      item.error = e.toString();
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }

    return item;
  }

  Future<DownloadItem> startHlsDownload({
    required String url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
  }) async {
    if (kIsWeb) throw UnsupportedError('Downloads are not supported on web.');
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Storage permission denied');

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      title: title,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      fileExtension: '.m3u8',
      status: DownloadStatus.downloading,
    );

    _downloads.insert(0, item);
    _saveDownloads();

    _startHlsTask(item);

    return item;
  }

  Future<void> _startHlsTask(DownloadItem item) async {
    final dir = await getDownloadDirectory();
    final folderName = item.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final saveDirectory = '${dir.path}/$folderName';

    item.localPath = '$saveDirectory/local_playlist.m3u8';
    
    final service = HlsDownloaderService();
    _activeHlsDownloads[item.id] = service;

    service.onProgress = (progress, downloaded, total) {
      item.progress = progress;
      item.downloadedBytes = downloaded;
      item.totalBytes = total;
      item.status = DownloadStatus.downloading;
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onError = (error) {
      item.status = DownloadStatus.failed;
      item.error = error;
      _activeHlsDownloads.remove(item.id);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onComplete = (localPath) {
      item.status = DownloadStatus.completed;
      item.localPath = localPath;
      item.completedAt = DateTime.now();
      _activeHlsDownloads.remove(item.id);
      onDownloadComplete?.call(item);
      _saveDownloads();
    };

    service.startDownload(
      m3u8Url: item.url,
      saveDirectory: saveDirectory,
    );
  }

  Future<void> pauseDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;
    
    if (item.fileExtension == '.m3u8') {
      _activeHlsDownloads[item.id]?.pause();
      item.status = DownloadStatus.paused;
      _saveDownloads();
      onDownloadUpdate?.call(item);
      return;
    }

    if (item.taskId != null) {
      await FlutterDownloader.pause(taskId: item.taskId!);
      item.status = DownloadStatus.paused;
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }
  }

  Future<void> resumeDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;
    
    if (item.fileExtension == '.m3u8') {
      if (_activeHlsDownloads.containsKey(item.id)) {
        _activeHlsDownloads[item.id]?.resume();
      } else {
        _startHlsTask(item);
      }
      item.status = DownloadStatus.downloading;
      _saveDownloads();
      onDownloadUpdate?.call(item);
      return;
    }

    if (item.taskId != null) {
      final taskId = await FlutterDownloader.resume(taskId: item.taskId!);
      item.taskId = taskId;
      item.status = DownloadStatus.downloading;
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }
  }

  Future<void> cancelDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;
    
    if (item.fileExtension == '.m3u8') {
      _activeHlsDownloads[item.id]?.cancel();
      _activeHlsDownloads.remove(id);
    } else if (item.taskId != null) {
      await FlutterDownloader.cancel(taskId: item.taskId!);
    }
    item.status = DownloadStatus.canceled;
    _saveDownloads();
    onDownloadUpdate?.call(item);
  }

  Future<void> deleteDownload(String id) async {
    final item = _findById(id);
    if (item == null) return;
    
    if (item.fileExtension == '.m3u8') {
      _activeHlsDownloads[item.id]?.cancel();
      _activeHlsDownloads.remove(id);
      
      if (item.localPath != null && !kIsWeb) {
        final file = File(item.localPath!);
        final parentDir = file.parent;
        if (await parentDir.exists()) {
          await parentDir.delete(recursive: true);
        }
      }
    } else {
      if (item.localPath != null && !kIsWeb) {
        final file = File(item.localPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
    
    _downloads.removeWhere((d) => d.id == id);
    _saveDownloads();
  }

  Future<void> clearCompleted() async {
    _downloads.removeWhere((d) => d.status == DownloadStatus.completed);
    _saveDownloads();
  }

  /// Safe find by id
  DownloadItem? _findById(String id) {
    for (final d in _downloads) {
      if (d.id == id) return d;
    }
    return null;
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
}
