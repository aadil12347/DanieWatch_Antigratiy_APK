import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/manifest_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/custom_pull_to_refresh.dart';

class AnimeScreen extends ConsumerWidget {
  const AnimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anime = ref.watch(animeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: CustomDrawer(),
      body: CustomAppBar(
        extendBehindAppBar: false,
        child: anime.isEmpty
            ? const Center(child: ShimmerGrid())
            : CustomPullToRefresh(
                onRefresh: () async {
                  ref.invalidate(animeProvider);
                  await Future.delayed(const Duration(milliseconds: 800));
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        top: 16,
                        left: 12,
                        right: 12,
                        bottom: 8,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => MovieCard(item: anime[index]),
                          childCount: anime.length,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
      ),
    );
  }
}
