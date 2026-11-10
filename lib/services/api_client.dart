import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// خطأ برسالة عربية واضحة تُعرض للمستخدم كما هي
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);

  bool get isNetwork => statusCode == null;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

enum ApiRole { student, cafeteria }

/// الاتصال بسيرفر وجباتي (FastAPI)
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _kUrl = 'wajbati.apiUrl';
  static const _kStudentToken = 'wajbati.studentToken';
  static const _kCafeteriaToken = 'wajbati.cafeteriaToken';
  static const timeout = Duration(seconds: 12);

  /// يمكن تحديده وقت البناء: flutter run --dart-define=API_URL=http://192.168.1.10:8000
  static const _definedUrl = String.fromEnvironment('API_URL');

  http.Client _http = http.Client();
  SharedPreferences? _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String baseUrl = defaultUrl;
  String? studentToken;
  String? cafeteriaToken;

  static String get defaultUrl {
    if (_definedUrl.isNotEmpty) return _definedUrl;
    // محاكي أندرويد يصل لجهاز الكمبيوتر عبر 10.0.2.2
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  Future<void> init({http.Client? client}) async {
    if (client != null) _http = client;
    studentToken = null;
    cafeteriaToken = null;
    try {
      _prefs = await SharedPreferences.getInstance();
      baseUrl = _prefs!.getString(_kUrl) ?? defaultUrl;
      studentToken = await _readToken(_kStudentToken);
      cafeteriaToken = await _readToken(_kCafeteriaToken);
    } catch (e) {
      debugPrint('تعذّر قراءة الإعدادات المحفوظة: $e');
    }
  }

  Future<String?> _readToken(String key) async {
    final stored = await _secureStorage.read(key: '$baseUrl.$key');
    final legacy = _prefs?.getString(key);
    if (legacy != null) {
      // Migrate existing sessions before removing their plaintext copy.
      if (stored == null) {
        await _secureStorage.write(key: '$baseUrl.$key', value: legacy);
      }
      await _prefs?.remove(key);
    }
    return stored ?? legacy;
  }

  Future<void> setBaseUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) u = defaultUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (baseUrl != u) {
      // Never send a session issued by one server to a different server.
      studentToken = null;
      cafeteriaToken = null;
    }
    baseUrl = u;
    await _prefs?.setString(_kUrl, u);
  }

  Future<void> setToken(ApiRole role, String? token) async {
    final key = role == ApiRole.student ? _kStudentToken : _kCafeteriaToken;
    if (role == ApiRole.student) {
      studentToken = token;
    } else {
      cafeteriaToken = token;
    }
    if (token == null) {
      await _secureStorage.delete(key: '$baseUrl.$key');
      await _prefs?.remove(key);
    } else {
      await _secureStorage.write(key: '$baseUrl.$key', value: token);
      await _prefs?.remove(key);
    }
  }

  /// فحص الاتصال بالسيرفر
  Future<bool> ping([String? url]) async {
    try {
      final r = await _http
          .get(Uri.parse('${url ?? baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> get(
    String path, {
    ApiRole? auth,
    Map<String, String>? query,
  }) => _send('GET', path, auth: auth, query: query);
  Future<dynamic> post(String path, {ApiRole? auth, Object? body}) =>
      _send('POST', path, auth: auth, body: body);
  Future<dynamic> put(String path, {ApiRole? auth, Object? body}) =>
      _send('PUT', path, auth: auth, body: body);
  Future<dynamic> patch(String path, {ApiRole? auth, Object? body}) =>
      _send('PATCH', path, auth: auth, body: body);
  Future<dynamic> delete(String path, {ApiRole? auth}) =>
      _send('DELETE', path, auth: auth);

  /// رفع ملف (مثل صورة صنف) بصيغة multipart/form-data
  Future<dynamic> upload(
    String path,
    List<int> bytes,
    String filename, {
    required ApiRole auth,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final token = auth == ApiRole.student ? studentToken : cafeteriaToken;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 60)),
      );
    } on TimeoutException {
      throw const ApiException(
        'انتهت مهلة رفع الصورة، تحقق من الاتصال وحاول مجدداً.',
      );
    } catch (_) {
      throw const ApiException('تعذّر رفع الصورة. تحقق من الاتصال بالسيرفر.');
    }
    return _decode(res);
  }

  /// يحوّل رابط صورة نسبياً من السيرفر (/menu/1/image) إلى رابط كامل
  String resolveUrl(String url) => url.startsWith('/') ? '$baseUrl$url' : url;

  Future<dynamic> _send(
    String method,
    String path, {
    ApiRole? auth,
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = switch (auth) {
      ApiRole.student => studentToken,
      ApiRole.cafeteria => cafeteriaToken,
      null => null,
    };
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(
        await _http.send(req).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        'السيرفر لا يستجيب، تحقق من اتصالك بالإنترنت وحاول مجدداً.',
      );
    } catch (_) {
      throw const ApiException(
        'تعذّر الاتصال بالسيرفر. تحقق من الإنترنت أو من عنوان السيرفر.',
      );
    }
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    final detail = data is Map ? data['detail'] : null;
    final message = detail is String
        ? detail
        : res.statusCode >= 500
        ? 'حدث خطأ في السيرفر، حاول بعد قليل.'
        : 'تعذّر تنفيذ العملية (${res.statusCode}).';
    throw ApiException(message, res.statusCode);
  }
}
