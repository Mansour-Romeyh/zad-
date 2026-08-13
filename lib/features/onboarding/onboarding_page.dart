import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets/remote_image.dart';
import '../../data/content_repository.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/onboarding_card.dart';

/// One onboarding slide as displayed: either a backend slide (PRD F2
/// `content.get_onboarding`, remote image) or a bundled fallback (l10n
/// copy + asset image).
class _SlideData {
  const _SlideData({required this.title, required this.body, this.imageUrl, this.assetPath});

  final String title;
  final String body;
  final String? imageUrl;
  final String? assetPath;
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  /// Backend slides once fetched; null → bundled fallback. The bundled
  /// pages render immediately (no blank loading screen) and are simply
  /// replaced if the fetch lands with content.
  List<_SlideData>? _remoteSlides;

  static const _bundledImages = <String>[
    'assets/images/onboarding_delivery.png',
    'assets/images/produce_spread.png',
    'assets/images/produce_spread.png',
  ];

  static const _fetchTimeout = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _loadSlides();
  }

  Future<void> _loadSlides() async {
    try {
      final slides = await context
          .read<ContentRepository>()
          .getOnboarding()
          .timeout(_fetchTimeout);
      if (!mounted || slides.isEmpty) return;
      setState(() {
        _remoteSlides = [
          for (final slide in slides)
            _SlideData(
              title: slide.title,
              body: slide.subtitle ?? '',
              imageUrl: slide.imageUrl,
            ),
        ];
        _index = 0;
      });
    } catch (_) {
      // API unavailable → the bundled 3 pages stay (PRD F2 fallback).
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOnboardingDoneKey, true);
    } catch (_) {
      // Storage unavailable: re-showing onboarding next launch is benign.
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  List<_SlideData> _bundledSlides(AppLocalizations l10n) {
    final titles = [l10n.onb1Title, l10n.onb2Title, l10n.onb3Title];
    final bodies = [l10n.onb1Body, l10n.onb2Body, l10n.onb3Body];
    return [
      for (var i = 0; i < _bundledImages.length; i++)
        _SlideData(title: titles[i], body: bodies[i], assetPath: _bundledImages[i]),
    ];
  }

  void _next(int count) {
    if (_index < count - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = _remoteSlides ?? _bundledSlides(l10n);
    final safeIndex = _index < slides.length ? _index : slides.length - 1;

    return Scaffold(
      backgroundColor: ZadColors.paleGreen,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: _finish,
                    borderRadius: BorderRadius.circular(20),
                    child: Row(
                      children: [
                        Text(
                          l10n.skip,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: ZadColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: ZadColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: slides.length,
              itemBuilder: (context, i) {
                final slide = slides[i];
                final placeholder = Image.asset(
                  _bundledImages[i % _bundledImages.length],
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: slide.assetPath != null
                      ? placeholder
                      : RemoteImage(
                          url: slide.imageUrl,
                          placeholder: placeholder,
                          fit: BoxFit.contain,
                        ),
                );
              },
            ),
          ),
          OnboardingCard(
            index: safeIndex,
            count: slides.length,
            title: slides[safeIndex].title,
            body: slides[safeIndex].body,
            onNext: () => _next(slides.length),
          ),
        ],
      ),
    );
  }
}
