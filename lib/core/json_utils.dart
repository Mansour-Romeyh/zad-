/// Small defensive JSON parsing helpers shared by model `fromJson` factories.
///
/// The backend (Frappe) returns numbers, booleans and even `null` in loosely
/// typed ways (e.g. a boolean flag as `1`/`0`, or a decimal as a string), so
/// every model that parses JSON goes through these helpers instead of
/// unsafe casts.
library;

double? toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? toInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool toBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == '1' || value.toLowerCase() == 'true';
  return fallback;
}
