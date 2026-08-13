import 'package:dio/dio.dart';

/// Builds a response (or throws to signal an error) for a captured request.
typedef FakeDioHandler = Response<dynamic> Function(RequestOptions options);

/// A [Dio] instance wired with an interceptor that never touches the
/// network: every request is answered synchronously by [handler]. Statuses
/// >= 400 are turned into a [DioException] the same way a real HTTP call
/// would produce, so [ApiClient]'s error mapping can be exercised without
/// any real I/O.
Dio buildFakeDio(
  FakeDioHandler handler, {
  String baseUrl = 'http://test.local',
  List<RequestOptions>? capturedRequests,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, interceptorHandler) {
        capturedRequests?.add(options);
        final response = handler(options);
        if (response.statusCode != null && response.statusCode! >= 400) {
          interceptorHandler.reject(
            DioException(
              requestOptions: options,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        } else {
          interceptorHandler.resolve(response);
        }
      },
    ),
  );
  return dio;
}

/// A fake dio that fails with a connection-level [DioException] (no
/// response), simulating offline/timeout conditions.
Dio buildNetworkErrorDio({
  String baseUrl = 'http://test.local',
  DioExceptionType type = DioExceptionType.connectionError,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, interceptorHandler) {
        interceptorHandler.reject(
          DioException(requestOptions: options, type: type),
        );
      },
    ),
  );
  return dio;
}
