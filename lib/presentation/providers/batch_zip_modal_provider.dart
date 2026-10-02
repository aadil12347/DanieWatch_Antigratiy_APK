import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/content_detail.dart';

class BatchZipModalState {
  final bool isOpen;
  final ContentDetail? content;
  final int seasonNumber;
  final String? postUrl;

  const BatchZipModalState({
    this.isOpen = false,
    this.content,
    this.seasonNumber = 1,
    this.postUrl,
  });
}

final batchZipModalProvider = StateProvider<BatchZipModalState>((ref) {
  return const BatchZipModalState();
});
