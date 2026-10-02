import 'package:flutter/material.dart';
import 'dart:async';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool autoNavigate;
  const SplashScreen({super.key, this.autoNavigate = true});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    debugPrint("EDU_RDC_DEBUG: SplashScreen initState started");

    // Logo entrance animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    // Text fade-in
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.3, 1.0, curve: Curves.easeIn)),
    );

    // Loading pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start animations
    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _fadeController.forward();
    });

    // Navigate only if enabled (splash court)
    if (widget.autoNavigate) {
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const DashboardScreen(),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("EDU_RDC_DEBUG: SplashScreen build() called");
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: Stack(
          children: [

            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Container(
                            width: 130,
                            height: 130,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // App name
                  AnimatedBuilder(
                    animation: _fadeController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textOpacity.value,
                        child: Column(
                          children: [
                            RichText(
                              text: const TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Yekola',
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Opacity(
                              opacity: _subtitleOpacity.value,
                              child: const Text(
                                'Votre plateforme éducative',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 60),

                  // Loading indicator
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _pulseAnimation.value,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (index) {
                            return AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, __) {
                                final delay = index * 0.15;
                                final progress = (_pulseController.value + delay) % 1.0;
                                final scale = 0.5 + (progress < 0.5 ? progress : 1.0 - progress);
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 10 * scale,
                                  height: 10 * scale,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D47A1).withValues(alpha: 0.3 + 0.7 * scale),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom branding
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _fadeController,
                builder: (_, __) {
                  return Opacity(
                    opacity: _subtitleOpacity.value * 0.6,
                    child: const Column(
                      children: [
                        Text(
                          'MADE IN DRC 🇨🇩',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'v1.0.0',
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
