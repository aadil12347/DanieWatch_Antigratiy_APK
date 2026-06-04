import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/splash_provider.dart';
import 'auth_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  List<String> col1 = [];
  List<String> col2 = [];
  List<String> col3 = [];
  bool _isLogin = true;

  @override
  void initState() {
    super.initState();
    _checkFirstRun();
  }
  
  void _initializePosters(List<String> allPosters) {
    if (allPosters.isEmpty || col1.isNotEmpty) return;
    final shuffled = List<String>.from(allPosters)..shuffle();
    final count = (shuffled.length / 3).floor();
    if (mounted) {
      setState(() {
        col1 = shuffled.sublist(0, count);
        col2 = shuffled.sublist(count, count * 2);
        col3 = shuffled.sublist(count * 2);
      });
    }
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = prefs.getBool('is_first_run') ?? true;
    if (mounted) setState(() => _isLogin = !isFirstRun);
    if (isFirstRun) await prefs.setBool('is_first_run', false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<String>>>(trendingPostersProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        _initializePosters(next.value!);
      }
    });
    final postersAsync = ref.watch(trendingPostersProvider);
    if (postersAsync.hasValue && col1.isEmpty) {
      Future.microtask(() => _initializePosters(postersAsync.value!));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (col1.isNotEmpty)
            Row(
              children: [
                Expanded(child: MarqueeSubColumn(images: col1, speed: 40, isReverse: false)),
                const SizedBox(width: 8),
                Expanded(child: MarqueeSubColumn(images: col2, speed: 30, isReverse: true)),
                const SizedBox(width: 8),
                Expanded(child: MarqueeSubColumn(images: col3, speed: 50, isReverse: false)),
              ],
            ),
          Positioned(
            top: 0, left: 0, right: 0, height: 250,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.95), Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0, height: 350,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(1.0), Colors.black.withOpacity(0.8), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: AuthScreen(
                  isLogin: _isLogin,
                  onToggle: () => setState(() => _isLogin = !_isLogin),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarqueeSubColumn extends StatefulWidget {
  final List<String> images;
  final double speed;
  final bool isReverse;

  const MarqueeSubColumn({super.key, required this.images, required this.speed, this.isReverse = false});

  @override
  State<MarqueeSubColumn> createState() => _MarqueeSubColumnState();
}

class _MarqueeSubColumnState extends State<MarqueeSubColumn> {
  late ScrollController _scrollController;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: widget.isReverse ? 2000 : 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted || !_scrollController.hasClients) {
        timer.cancel();
        return;
      }
      try {
        double maxScroll = _scrollController.position.maxScrollExtent;
        double currentScroll = _scrollController.offset;
        if (widget.isReverse) {
          double nextScroll = currentScroll - (widget.speed / 100);
          _scrollController.jumpTo(nextScroll <= 0 ? maxScroll / 2 : nextScroll);
        } else {
          double nextScroll = currentScroll + (widget.speed / 100);
          _scrollController.jumpTo(nextScroll >= maxScroll ? maxScroll / 2 : nextScroll);
        }
      } catch (_) { timer.cancel(); }
    });
  }

  @override
  void dispose() {
    if (_timer.isActive) _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extended = [...widget.images, ...widget.images, ...widget.images, ...widget.images];
    return ListView.builder(
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: extended.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              extended[index], height: 170, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(height: 170, color: Colors.white10),
            ),
          ),
        );
      },
    );
  }
}
