import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/splash_poster_model.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import 'package:provider/provider.dart';
import 'package:belive/widgets/preloader.dart';

/// Splash poster screen — shows a full-screen poster image for [duration]
/// seconds on app startup, then navigates to the normal splash screen.
///
/// The poster image, duration, and enabled flag are controlled from the
/// admin panel via the GET /splashPoster endpoint.
///
/// If the poster is disabled, not found, or fails to load, the screen
/// immediately navigates to the splash screen.
class SplashPosterScreen extends StatefulWidget {
  const SplashPosterScreen({super.key});

  @override
  State<SplashPosterScreen> createState() => _SplashPosterScreenState();
}

class _SplashPosterScreenState extends State<SplashPosterScreen> {
  static const String _tag = 'SplashPoster';
  bool _hasNavigated = false;
  Timer? _timer;
  SplashPoster? _poster;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPoster();
  }

  Future<void> _fetchPoster() async {
    try {
      final res = await ApiService.getSplashPoster();
      if (res.status && res.data != null && res.data!.enabled) {
        _poster = res.data;
        if (mounted) setState(() => _loading = false);
        // Start timer once image is loaded (or fallback timer)
        _startNavigationTimer();
      } else {
        _navigateToSplash();
      }
    } catch (e) {
      Log.e(_tag, 'fetchPoster failed', e);
      _navigateToSplash();
    }
  }

  void _startNavigationTimer() {
    final seconds = _poster?.duration ?? 4;
    _timer = Timer(Duration(seconds: seconds), _navigateToSplash);
  }

  void _navigateToSplash() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _timer?.cancel();

    // Always route through the splash screen so it can verify the device
    // block status before allowing access to the main app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/${AppRoutes.splash}');
    });
  }

  void _skip() {
    _navigateToSplash();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.themed(context, 0xFF000000, 0xFFFAFAFE),
      body: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [
          // Poster image or loading state
          if (_loading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/unilive_logo.png',
                    width: 100,
                    height: 100,
                  ),
                  const SizedBox(height: 20),
                  Preloader(color: AppTheme.fg(context)),
                ],
              ),
            )
          else if (_poster != null &&
              _poster!.image != null &&
              _poster!.image!.isNotEmpty)
            GestureDetector(
              onTap: _skip,
              child: CachedNetworkImage(
                imageUrl: _poster!.image!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder:
                    (context, url) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/unilive_logo.png',
                            width: 100,
                            height: 100,
                          ),
                          const SizedBox(height: 20),
                          const Preloader(color: Colors.white),
                        ],
                      ),
                    ),
                errorWidget: (context, url, error) {
                  // If image fails to load, navigate immediately
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _navigateToSplash(),
                  );
                  return Center(
                    child: Image.asset(
                      'assets/images/unilive_logo.png',
                      width: 100,
                      height: 100,
                    ),
                  );
                },
              ),
            )
          else
            Center(
              child: Image.asset(
                'assets/images/unilive_logo.png',
                width: 100,
                height: 100,
              ),
            ),

          // Skip button (top-right corner)
          if (!_loading && _poster != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: _skip,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          // Progress indicator at bottom
          if (!_loading && _poster != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: const Center(
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
