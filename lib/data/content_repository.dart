import '../core/api/api_client.dart';
import '../models/app_banner.dart';
import '../models/app_config.dart';
import '../models/onboarding_slide.dart';

/// Thin, typed wrapper over `grocery.api.content.*` and
/// `grocery.api.home.get_banners` (PRD Part F2). Guest-accessible (read).
class ContentRepository {
  ContentRepository(this._client);

  final ApiClient _client;

  Future<List<OnboardingSlide>> getOnboarding() async {
    final data = await _client.get('grocery.api.content.get_onboarding');
    return _mapList(data, OnboardingSlide.fromJson);
  }

  Future<AppConfig> getAppConfig() async {
    final data = await _client.get('grocery.api.content.get_app_config');
    return AppConfig.fromJson(
      data as Map<String, dynamic>,
      resolveImageUrl: _client.resolveFileUrl,
    );
  }

  Future<List<AppBannerModel>> getBanners() async {
    final data = await _client.get('grocery.api.home.get_banners');
    return _mapList(data, AppBannerModel.fromJson);
  }

  List<T> _mapList<T>(
    dynamic data,
    T Function(Map<String, dynamic>, {String? Function(String?)? resolveImageUrl}) fromJson,
  ) {
    if (data is! List) return const [];
    return data
        .map(
          (e) => fromJson(
            e as Map<String, dynamic>,
            resolveImageUrl: _client.resolveFileUrl,
          ),
        )
        .toList();
  }
}
