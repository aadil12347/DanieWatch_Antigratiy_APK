import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/manifest_item.dart';

/// Hero banner section with auto-scrolling featured content.
class HeroSection extends StatefulWidget {
  final List<ManifestItem> items;

  const HeroSection({super.key, required this.items});

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  late final PageController _controller;
  int _currentPage = 0;
  Timer? _autoScroll;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 1.0);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScroll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      if (widget.items.isEmpty) return;
      final nextPage = (_currentPage + 1) % widget.items.take(5).length;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final items = widget.items.take(5).toList();

    return SizedBox(
      height: 600,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final imageUrl = item.posterUrl ?? item.backdropUrl ?? '';
              final logoUrl = item.logoUrl;

              return GestureDetector(
                onTap: () => context.push('/details/${item.mediaType}/${item.id}'),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background image
                    if (imageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 800,
                        alignment: Alignment.topCenter,
                        errorWidget: (_, __, ___) =>
                            Container(color: AppColors.surface),
                      )
                    else
                      Container(color: AppColors.surface),

                    // Bottom gradient overlay (to make text readable)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.background.withOpacity(0.5),
                            AppColors.background,
                          ],
                          stops: const [0.3, 0.8, 1.0],
                        ),
                      ),
                    ),

                    // Content overlay at bottom
                    Positioned(
                      bottom: 40,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (logoUrl != null && logoUrl.isNotEmpty) ...[
                            CachedNetworkImage(
                              imageUrl: logoUrl,
                              height: 60,
                              alignment: Alignment.centerLeft,
                              errorWidget: (_, __, ___) => _buildTextTitle(item),
                            ),
                          ] else ...[
                            _buildTextTitle(item),
                          ],
                          
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Action, Superhero, Science Fiction, ...",
                                  style: TextStyle(
                                    color: AppColors.textPrimary.withOpacity(0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // Buttons
                          Row(
                            children: [
                              // Play Button
                              Expanded(
                                flex: 4,
                                child: ElevatedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.play_circle_fill, color: Colors.white, size: 22),
                                  label: const Text(
                                    'Play',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // My List Button
                              Expanded(
                                flex: 5,
                                child: OutlinedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.add, color: Colors.white, size: 22),
                                  label: const Text(
                                    'My List',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white, width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(flex: 2), // spacing buffer
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTextTitle(ManifestItem item) {
    return Text(
      item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
      ),
    );
  }
}
