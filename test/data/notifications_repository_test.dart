import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/notifications_repository.dart';

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

// notifications.list envelope exactly as the backend builds it.
const _listJson = {
  'items': [
    {
      'name': 'NL-0002',
      'title': 'تم تعديل طلبك',
      'body': '<p>تم تعديل الكمية</p>',
      'read': false,
      'creation': '2026-07-13 10:30:00.000000',
    },
    {
      'name': 'NL-0001',
      'title': 'تم استلام طلبك',
      'body': 'سيصلك قريباً',
      'read': 1, // frappe-style int boolean
      'creation': '2026-07-12 09:00:00.000000',
    },
  ],
  'page': 1,
  'has_more': true,
};

void main() {
  group('NotificationsRepository', () {
    test('list() calls notifications.list with the page and maps the envelope', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _listJson),
          capturedRequests: requests);
      final repo = NotificationsRepository(_client(dio));

      final result = await repo.list(page: 1);

      expect(requests.single.path, '/api/method/grocery.api.notifications.list');
      expect(requests.single.queryParameters, {'page': 1});
      expect(result.page, 1);
      expect(result.hasMore, isTrue); // straight from the envelope
      expect(result.items, hasLength(2));
      expect(result.items.first.name, 'NL-0002');
      expect(result.items.first.title, 'تم تعديل طلبك');
      expect(result.items.first.body, '<p>تم تعديل الكمية</p>');
      expect(result.items.first.read, isFalse);
      expect(result.items.first.creation, '2026-07-13 10:30:00.000000');
      expect(result.items.last.read, isTrue); // int 1 → bool
    });

    test('list() tolerates a missing/odd items payload', () async {
      final dio = buildFakeDio(
          (options) => _envelope(options, {'items': null, 'page': 3, 'has_more': false}));
      final repo = NotificationsRepository(_client(dio));

      final result = await repo.list(page: 3);

      expect(result.items, isEmpty);
      expect(result.page, 3);
      expect(result.hasMore, isFalse);
    });

    test('unreadCount() unwraps {count}', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'count': 4}),
          capturedRequests: requests);
      final repo = NotificationsRepository(_client(dio));

      expect(await repo.unreadCount(), 4);
      expect(requests.single.path,
          '/api/method/grocery.api.notifications.unread_count');
    });

    test('unreadCount() tolerates a malformed payload as 0', () async {
      final dio = buildFakeDio((options) => _envelope(options, null));
      final repo = NotificationsRepository(_client(dio));

      expect(await repo.unreadCount(), 0);
    });

    test('markRead() posts the name to notifications.mark_read', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'ok': true}),
          capturedRequests: requests);
      final repo = NotificationsRepository(_client(dio));

      await repo.markRead('NL-0002');

      expect(requests.single.path,
          '/api/method/grocery.api.notifications.mark_read');
      expect(requests.single.data, {'name': 'NL-0002'});
    });

    test('a guest 401 surfaces as UnauthenticatedException', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Please log in'},
        ),
      );
      final repo = NotificationsRepository(_client(dio));

      expect(repo.list(), throwsA(isA<UnauthenticatedException>()));
    });
  });
}
