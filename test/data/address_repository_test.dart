import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/address_repository.dart';

import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

ApiClient _client(Dio dio) => ApiClient(
      dio: dio,
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

// address.list rows as the backend returns them (default first; list rows
// never carry zone fields — those appear on create/update only).
const _addressesJson = [
  {
    'name': 'ADDR-2',
    'label': 'Work',
    'address_line': 'Office 4, Karrada St',
    'city': 'Baghdad',
    'lat': 33.31,
    'lng': 44.37,
    'is_default': 1,
  },
  {
    'name': 'ADDR-1',
    'label': 'Home',
    'address_line': 'House 12, Al-Mansour',
    'city': 'Baghdad',
    'lat': 0.0,
    'lng': 0.0,
    'is_default': 0,
  },
];

void main() {
  group('AddressRepository', () {
    test('list() calls address.list and maps rows in server order', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _addressesJson),
          capturedRequests: requests);
      final repo = AddressRepository(_client(dio));

      final addresses = await repo.list();

      expect(requests.single.path, '/api/method/grocery.api.address.list');
      expect(addresses, hasLength(2));
      expect(addresses.first.name, 'ADDR-2');
      expect(addresses.first.label, 'Work');
      expect(addresses.first.addressLine, 'Office 4, Karrada St');
      expect(addresses.first.city, 'Baghdad');
      expect(addresses.first.lat, 33.31);
      expect(addresses.first.isDefault, isTrue);
      expect(addresses.first.hasCoordinates, isTrue);
      expect(addresses.first.zoneName, isNull); // list rows carry no zone
      expect(addresses.last.isDefault, isFalse);
      expect(addresses.last.hasCoordinates, isFalse); // (0,0) sentinel
    });

    test('list() tolerates a non-list payload', () async {
      final dio = buildFakeDio((options) => _envelope(options, null));
      final repo = AddressRepository(_client(dio));

      expect(await repo.list(), isEmpty);
    });

    test('create() posts the exact PRD F4 field names and parses zone info', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'name': 'ADDR-7',
          'label': 'Home',
          'address_line': 'House 12',
          'city': 'Baghdad',
          'lat': 33.31,
          'lng': 44.37,
          'is_default': 1,
          'zone': {'zone_name': 'Central', 'warehouse': 'Main Store - GR'},
        }),
        capturedRequests: requests,
      );
      final repo = AddressRepository(_client(dio));

      final created = await repo.create(
        label: 'Home',
        addressLine: 'House 12',
        city: 'Baghdad',
        lat: 33.31,
        lng: 44.37,
        isDefault: true,
      );

      expect(requests.single.path, '/api/method/grocery.api.address.create');
      expect(requests.single.data, {
        'label': 'Home',
        'address_line': 'House 12',
        'city': 'Baghdad',
        'lat': 33.31,
        'lng': 44.37,
        'is_default': 1,
      });
      expect(created.name, 'ADDR-7');
      expect(created.isDefault, isTrue);
      expect(created.zoneName, 'Central');
      expect(created.warehouse, 'Main Store - GR');
      expect(created.outsideCoverage, isFalse);
    });

    test('create() parses an outside-coverage response (address still returned)', () async {
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'name': 'ADDR-8',
          'label': 'Other',
          'address_line': 'Far away',
          'city': 'Basra',
          'lat': 30.5,
          'lng': 47.8,
          'is_default': 0,
          'outside_coverage': true,
        }),
      );
      final repo = AddressRepository(_client(dio));

      final created = await repo.create(
        label: 'Other', addressLine: 'Far away', city: 'Basra', lat: 30.5, lng: 47.8);

      expect(created.name, 'ADDR-8');
      expect(created.outsideCoverage, isTrue);
      expect(created.zoneName, isNull);
    });

    test('update() sends only the provided fields (partial update)', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'name': 'ADDR-1',
          'label': 'Work',
          'address_line': 'House 12',
          'city': 'Baghdad',
          'lat': 0,
          'lng': 0,
          'is_default': 0,
          'outside_coverage': true,
        }),
        capturedRequests: requests,
      );
      final repo = AddressRepository(_client(dio));

      await repo.update('ADDR-1', label: 'Work');

      expect(requests.single.path, '/api/method/grocery.api.address.update');
      expect(requests.single.data, {'name': 'ADDR-1', 'label': 'Work'});
    });

    test('delete() and setDefault() post the address name', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'ok': true}),
          capturedRequests: requests);
      final repo = AddressRepository(_client(dio));

      await repo.delete('ADDR-1');
      await repo.setDefault('ADDR-2');

      expect(requests[0].path, '/api/method/grocery.api.address.delete');
      expect(requests[0].data, {'name': 'ADDR-1'});
      expect(requests[1].path, '/api/method/grocery.api.address.set_default');
      expect(requests[1].data, {'name': 'ADDR-2'});
    });

    test('resolveZone() maps a covered point', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'warehouse': 'Main Store - GR', 'zone_name': 'Central'}),
        capturedRequests: requests,
      );
      final repo = AddressRepository(_client(dio));

      final zone = await repo.resolveZone(33.31, 44.37);

      expect(requests.single.path, '/api/method/grocery.api.zone.resolve');
      expect(requests.single.queryParameters, {'lat': 33.31, 'lng': 44.37});
      expect(zone.covered, isTrue);
      expect(zone.zoneName, 'Central');
      expect(zone.warehouse, 'Main Store - GR');
    });

    test('resolveZone() maps an outside-coverage point', () async {
      final dio = buildFakeDio((options) => _envelope(options, {'outside_coverage': true}));
      final repo = AddressRepository(_client(dio));

      final zone = await repo.resolveZone(1.0, 2.0);

      expect(zone.covered, isFalse);
      expect(zone.outsideCoverage, isTrue);
      expect(zone.zoneName, isNull);
    });

    test('a guest 401 surfaces as UnauthenticatedException', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Please log in'},
        ),
      );
      final repo = AddressRepository(_client(dio));

      expect(repo.list(), throwsA(isA<UnauthenticatedException>()));
    });
  });
}
