import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../providers/manifest_provider.dart';
import '../../widgets/content_row.dart';
import '../../widgets/hero_section.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_drawer.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync = ref.watch(manifestProvider);
    final sections = ref.watch(homeSectionsProvider);
    final trending = ref.watch(trendingProvider);

    return manifestAsync.when(
      loading: () => const _LoadingHome(),
      error: (e, _) => _ErrorHome(error: e.toString()),
      data: (manifest) {
        if (manifest == null || manifest.items.isEmpty) {
          return const _EmptyHome();
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: const CustomDrawer(),
          body: CustomAppBar(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Content sections
                if (trending.isNotEmpty)
                  SliverToBoxAdapter(
                    child: HeroSection(items: trending),
                  ),

                // Content sections
                ...sections.map((section) => SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(title: section.title),
                          ContentRow(items: section.items),
                        ],
                      ),
                    )),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 80),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingHome extends StatelessWidget {
  const _LoadingHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Hero shimmer
            const ShimmerBox(width: double.infinity, height: 220),
            const SizedBox(height: 24),
            // Section shimmers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerBox(width: 120, height: 18),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, __) =>
                          const ShimmerBox(width: 120, height: 180),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorHome extends StatelessWidget {
  final String error;
  const _ErrorHome({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No content available',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
