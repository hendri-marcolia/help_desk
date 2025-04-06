import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:help_desk/config.dart';
import 'login_screen.dart';

class DioClient {
  static final Dio _dio = Dio();
  static final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static final CacheOptions _cacheOptions = CacheOptions(
    store: MemCacheStore(),
    policy: CachePolicy.refreshForceCache,
    hitCacheOnErrorExcept: [401, 403],
    maxStale: const Duration(days: 1),
    priority: CachePriority.normal,
    keyBuilder: CacheOptions.defaultCacheKeyBuilder,
    allowPostMethod: false,
  );

  static Future<Dio> getInstance(BuildContext context) async {
    _dio.interceptors.clear();

    // Add cache interceptor
    _dio.interceptors.add(DioCacheInterceptor(options: _cacheOptions));

    // Read the auth_token from storage
    final authToken = await _storage.read(key: 'auth_token');
    if (authToken != null && authToken.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $authToken';
      _dio.options.headers['Content-Type'] = 'application/json';
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioError error, ErrorInterceptorHandler handler) async {
        if (error.response?.statusCode == 401 &&  (!error.requestOptions.path.endsWith('/auth/login') && !error.requestOptions.path.endsWith('$API_HOST/auth/refresh'))) {
          final refreshToken = await _storage.read(key: 'refresh_token');
          if (refreshToken != null && refreshToken.isNotEmpty) {
            try {
              final refreshResponse = await _dio.post(
                '$API_HOST/auth/refresh',
                data: {'refresh_token': refreshToken},
              );
              await _storage.write(key: 'auth_token', value: refreshResponse.data['token']);
              await _storage.write(key: 'refresh_token', value: refreshResponse.data['refresh_token']);
              await _storage.write(key: 'expires_in', value: refreshResponse.data['expires_in'].toString());

              // Retry the original request with the new token
              final options = error.requestOptions;
              _dio.options.headers['Authorization'] = 'Bearer ${refreshResponse.data['token']}';
              final response = await _dio.request(
                options.path,
                options: Options(
                  method: options.method,
                  headers: _dio.options.headers,
                ),
                data: options.data,
                queryParameters: options.queryParameters,
              );
              return handler.resolve(response);
            } catch (_) {
              await _logout(context); // Logout if refresh fails
            }
          } else {
            await _logout(context); // Logout if no refresh token exists
          }
        }
        return handler.next(error); // Pass the error if not handled
      },
    ));
    return _dio;
  }

  static Future<void> _logout(BuildContext context) async {
    await _storage.deleteAll();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }
}
