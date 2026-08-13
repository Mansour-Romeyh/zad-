import '../core/api/api_client.dart';
import '../core/json_utils.dart';

/// The server-side label values `address.create/update` accept (PRD F4 —
/// `LABEL_OPTIONS` in `address.py`). The UI shows them localized
/// (منزل/عمل/أخرى) but always sends these exact strings.
abstract final class AddressLabels {
  static const home = 'Home';
  static const work = 'Work';
  static const other = 'Other';
  static const all = [home, work, other];
}

/// Zone resolution for a coordinate pair — `zone.resolve` returns either
/// `{warehouse, zone_name}` or `{outside_coverage: true}` (PRD F4/E5).
/// `address.create/update` responses embed the same information
/// (`{zone: {...}}` / `{outside_coverage: true}`), parsed into
/// [AddressModel]'s zone fields.
class ZoneResult {
  const ZoneResult({this.zoneName, this.warehouse, this.outsideCoverage = false});

  final String? zoneName;
  final String? warehouse;
  final bool outsideCoverage;

  /// Whether the point falls inside an active delivery zone.
  bool get covered => !outsideCoverage && zoneName != null;

  factory ZoneResult.fromJson(dynamic json) {
    if (json is! Map) return const ZoneResult(outsideCoverage: true);
    return ZoneResult(
      zoneName: json['zone_name'] as String?,
      warehouse: json['warehouse'] as String?,
      outsideCoverage: toBool(json['outside_coverage']),
    );
  }
}

/// One address as returned by every `address.*` endpoint (PRD F4/D2):
/// `{name, label, address_line, city, lat, lng, is_default}` — plus, on
/// `create`/`update` responses only, the zone info for its coordinates
/// (`{zone: {zone_name, warehouse}}` or `{outside_coverage: true}`);
/// `list` rows never carry zone fields.
class AddressModel {
  const AddressModel({
    required this.name,
    required this.label,
    required this.addressLine,
    required this.city,
    this.lat,
    this.lng,
    this.isDefault = false,
    this.zoneName,
    this.warehouse,
    this.outsideCoverage = false,
  });

  /// Server document name — the id used by `update`/`delete`/`set_default`.
  final String name;

  /// One of [AddressLabels.all] (Home/Work/Other).
  final String label;
  final String addressLine;
  final String city;
  final double? lat;
  final double? lng;
  final bool isDefault;

  /// Zone fields (create/update responses only — `null`/`false` on `list`
  /// rows, which carry no zone info).
  final String? zoneName;
  final String? warehouse;
  final bool outsideCoverage;

  /// Whether this address carries real coordinates. The backend stores
  /// missing coordinates as `0` (`flt(None)`), and (0, 0) is no place a
  /// customer lives — treat it as "no location captured".
  bool get hasCoordinates => (lat ?? 0) != 0 || (lng ?? 0) != 0;

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    final zone = json['zone'];
    return AddressModel(
      name: json['name'] as String? ?? '',
      label: json['label'] as String? ?? '',
      addressLine: json['address_line'] as String? ?? '',
      city: json['city'] as String? ?? '',
      lat: toDouble(json['lat']),
      lng: toDouble(json['lng']),
      isDefault: toBool(json['is_default']),
      zoneName: zone is Map ? zone['zone_name'] as String? : null,
      warehouse: zone is Map ? zone['warehouse'] as String? : null,
      outsideCoverage: toBool(json['outside_coverage']),
    );
  }
}

/// Thin, typed wrapper over `grocery.api.address.*` + `zone.resolve` (PRD
/// F4). Every method requires a logged-in session — the backend returns
/// 401/403 for guests, surfaced as the typed exceptions from [ApiClient].
/// `AddressStore` only calls this while authed; guest entry points are
/// gated at the tap site (LoginRequiredSheet).
class AddressRepository {
  AddressRepository(this._client);

  final ApiClient _client;

  /// The caller's addresses, default first (server-ordered
  /// `custom_is_default desc, creation desc`).
  Future<List<AddressModel>> list() async {
    final data = await _client.get('grocery.api.address.list');
    if (data is! List) return const [];
    return data
        .map((e) => AddressModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Creates an address; the response includes zone info for its
  /// coordinates. `lat`/`lng` are required by the backend signature — pass
  /// `0` when no location was captured (stored as-is, resolves to outside
  /// coverage, which callers suppress when [AddressModel.hasCoordinates]
  /// is false).
  Future<AddressModel> create({
    required String label,
    required String addressLine,
    required String city,
    required double lat,
    required double lng,
    bool isDefault = false,
  }) async {
    final data = await _client.post(
      'grocery.api.address.create',
      data: {
        'label': label,
        'address_line': addressLine,
        'city': city,
        'lat': lat,
        'lng': lng,
        'is_default': isDefault ? 1 : 0,
      },
    );
    return AddressModel.fromJson(data as Map<String, dynamic>);
  }

  /// Partial update — only non-null fields are sent (the backend leaves
  /// omitted ones untouched). Returns the address plus zone info for its
  /// (possibly just-updated) coordinates.
  Future<AddressModel> update(
    String name, {
    String? label,
    String? addressLine,
    String? city,
    double? lat,
    double? lng,
    bool? isDefault,
  }) async {
    final data = await _client.post(
      'grocery.api.address.update',
      data: {
        'name': name,
        'label': ?label,
        'address_line': ?addressLine,
        'city': ?city,
        'lat': ?lat,
        'lng': ?lng,
        if (isDefault != null) 'is_default': isDefault ? 1 : 0,
      },
    );
    return AddressModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String name) async {
    await _client.post('grocery.api.address.delete', data: {'name': name});
  }

  /// Marks [name] as the default — the server clears any other default
  /// atomically; callers re-[list] to pick up the new exclusive ordering.
  Future<void> setDefault(String name) async {
    await _client.post('grocery.api.address.set_default', data: {'name': name});
  }

  /// `zone.resolve {lat, lng}` — coverage info for a point, independent of
  /// any saved address (used for instant feedback right after a location
  /// capture).
  Future<ZoneResult> resolveZone(double lat, double lng) async {
    final data = await _client.get(
      'grocery.api.zone.resolve',
      params: {'lat': lat, 'lng': lng},
    );
    return ZoneResult.fromJson(data);
  }
}
