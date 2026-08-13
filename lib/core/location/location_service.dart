import 'package:geolocator/geolocator.dart';

/// Why a current-location request failed — the address form maps each
/// reason to a localized, non-blocking message (manual entry always stays
/// usable, PRD A3 "location permission ... skippable").
enum LocationFailureReason {
  /// Device location services are switched off entirely.
  serviceDisabled,

  /// The user denied the permission prompt (this time).
  permissionDenied,

  /// The user denied permanently — only the OS settings screen can undo it.
  permissionDeniedForever,

  /// Permission was fine but the position could not be obtained (timeout,
  /// platform error…).
  unavailable,
}

/// Typed failure thrown by [LocationService.getCurrent].
class LocationException implements Exception {
  const LocationException(this.reason);

  final LocationFailureReason reason;

  @override
  String toString() => 'LocationException($reason)';
}

/// A device fix — just the coordinates the address APIs need (PRD F4
/// `lat`/`lng`).
class DeviceLocation {
  const DeviceLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

/// Injectable seam over platform location (provided above `MaterialApp`
/// like the repositories). Screens depend on this interface only, so tests
/// substitute a fake and never touch the geolocator platform channel.
abstract class LocationService {
  /// Resolves the device's current position, running the permission flow
  /// if needed. Throws [LocationException] on any failure.
  Future<DeviceLocation> getCurrent();
}

/// The real implementation over `geolocator` — the only file in the app
/// that imports the plugin.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<DeviceLocation> getCurrent() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(LocationFailureReason.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(LocationFailureReason.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailureReason.permissionDeniedForever,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return DeviceLocation(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      throw const LocationException(LocationFailureReason.unavailable);
    }
  }
}
