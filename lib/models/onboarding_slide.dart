import '../core/json_utils.dart';

/// A single onboarding slide (PRD F2 `content.get_onboarding`):
/// `{title, subtitle, image, sequence}`.
class OnboardingSlide {
  const OnboardingSlide({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.sequence,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final int? sequence;

  factory OnboardingSlide.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final resolver = resolveImageUrl ?? (String? p) => p;
    return OnboardingSlide(
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      imageUrl: resolver(json['image'] as String?),
      sequence: toInt(json['sequence']),
    );
  }
}
