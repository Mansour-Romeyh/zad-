import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/onboarding_slide.dart';

void main() {
  test('fromJson parses a full payload', () {
    final slide = OnboardingSlide.fromJson(
      {
        'title': 'Fresh groceries',
        'subtitle': 'Delivered fast',
        'image': '/files/onboard1.png',
        'sequence': 1,
      },
      resolveImageUrl: (p) => p == null ? null : 'http://test.local$p',
    );

    expect(slide.title, 'Fresh groceries');
    expect(slide.subtitle, 'Delivered fast');
    expect(slide.imageUrl, 'http://test.local/files/onboard1.png');
    expect(slide.sequence, 1);
  });

  test('fromJson tolerates a minimal payload', () {
    final slide = OnboardingSlide.fromJson({'title': 'Welcome'});

    expect(slide.title, 'Welcome');
    expect(slide.subtitle, isNull);
    expect(slide.imageUrl, isNull);
    expect(slide.sequence, isNull);
  });
}
