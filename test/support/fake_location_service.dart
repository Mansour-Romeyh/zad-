import 'package:zad/core/location/location_service.dart';

/// In-memory [LocationService] for widget tests — no geolocator, no
/// platform channel. Succeeds with [location] unless [failure] is set, in
/// which case every call throws the matching [LocationException].
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.location = const DeviceLocation(lat: 33.3152, lng: 44.3661),
    this.failure,
  });

  final DeviceLocation location;
  final LocationFailureReason? failure;

  /// How many times the form asked for a fix.
  int callCount = 0;

  @override
  Future<DeviceLocation> getCurrent() async {
    callCount++;
    final reason = failure;
    if (reason != null) throw LocationException(reason);
    return location;
  }
}
