import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/quality_selector_sheet.dart';

class DownloadModalState {
  final bool isOpen;
  final bool isLoading;
  final String? m3u8Url;
  final String? title;
  final int? season;
  final int? episode;
  final void Function(DownloadSelection)? onSelected;
  final void Function()? onCancel;

  const DownloadModalState({
    this.isOpen = false,
    this.isLoading = false,
    this.m3u8Url,
    this.title,
    this.season,
    this.episode,
    this.onSelected,
    this.onCancel,
  });

  DownloadModalState copyWith({
    bool? isOpen,
    bool? isLoading,
    String? m3u8Url,
    String? title,
    int? season,
    int? episode,
    void Function(DownloadSelection)? onSelected,
    void Function()? onCancel,
  }) {
    return DownloadModalState(
      isOpen: isOpen ?? this.isOpen,
      isLoading: isLoading ?? this.isLoading,
      m3u8Url: m3u8Url ?? this.m3u8Url,
      title: title ?? this.title,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      onSelected: onSelected ?? this.onSelected,
      onCancel: onCancel ?? this.onCancel,
    );
  }
}

final downloadModalProvider = StateProvider<DownloadModalState>((ref) {
  return const DownloadModalState();
});
