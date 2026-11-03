import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;

  ApiException(this.statusCode, this.message, [this.data]);

  @override
  String toString() => message;
}

class ApiClient extends ChangeNotifier {
  static final ApiClient instance = ApiClient._internal();
  ApiClient._internal();

  static const List<String> fallbackBaseUrls = [
    'http://127.0.0.1:5284',
    'http://172.16.2.207:5284',
    'http://192.168.1.10:5284',
    'http://10.0.2.2:5284',
    'http://localhost:5284',
  ];

  String _baseUrl = (!kIsWeb && Platform.isAndroid)
      ? 'http://127.0.0.1:5284'
      : 'http://localhost:5284';

  String? _accessToken;
  Map<String, dynamic>? _currentUser;
  bool _isGuestMode = false;

  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _accessToken != null && _currentUser != null;
  bool get isGuestMode => _isGuestMode;

  List<String> get roles {
    final raw = _currentUser?['roles'] ?? _currentUser?['Roles'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const ['Customer'];
  }

  bool get isDriver => roles.contains('Driver');
  bool get isStaff => roles.contains('Staff');
  bool get isOperator => roles.contains('BusOperator');
  bool get isAdmin => roles.contains('Admin');

  void setBaseUrl(String url) {
    _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    notifyListeners();
  }

  void enterGuestMode() {
    _isGuestMode = true;
    notifyListeners();
  }

  void setSession(String token, Map<String, dynamic> user) {
    _accessToken = token;
    _currentUser = user;
    _isGuestMode = false;
    notifyListeners();
  }

  void updateCurrentUserFields(String fullName, String phone) {
    if (_currentUser != null) {
      _currentUser!['fullName'] = fullName;
      _currentUser!['FullName'] = fullName;
      _currentUser!['phone'] = phone;
      _currentUser!['Phone'] = phone;
      notifyListeners();
    }
  }

  void logout() {
    _accessToken = null;
    _currentUser = null;
    _isGuestMode = false;
    notifyListeners();
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final candidates = <String>[
      _baseUrl,
      ...fallbackBaseUrls.where((u) => u != _baseUrl),
    ];

    SocketException? lastSocketError;

    for (final candidateUrl in candidates) {
      try {
        final result = await _sendSingleRequest(
          candidateUrl,
          method,
          path,
          body: body,
          query: query,
        );
        if (candidateUrl != _baseUrl) {
          _baseUrl = candidateUrl;
          notifyListeners();
        }
        return result;
      } on SocketException catch (e) {
        lastSocketError = e;
        continue;
      }
    }

    throw ApiException(
      0,
      'Không thể kết nối tới Web API (đã thử $_baseUrl, USB 127.0.0.1:5284 và Wi-Fi 192.168.1.10:5284). Chi tiết: ${lastSocketError?.message ?? "No route"}',
    );
  }

  Future<dynamic> _sendSingleRequest(
    String targetBaseUrl,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    try {
      var uri = Uri.parse('$targetBaseUrl$path');
      if (query != null && query.isNotEmpty) {
        uri = uri.replace(queryParameters: query);
      }

      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_accessToken != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
      }

      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }

      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      dynamic decoded;
      if (text.isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          decoded = {'message': text};
        }
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return decoded;
      } else {
        String msg = 'Lỗi máy chủ (${resp.statusCode})';
        if (decoded is Map<String, dynamic>) {
          msg = (decoded['message'] ?? decoded['Message'] ?? decoded['title'] ?? msg).toString();
        }
        throw ApiException(
          resp.statusCode,
          msg,
          decoded is Map<String, dynamic> ? decoded : null,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      request('POST', path, body: body);

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) =>
      request('PUT', path, body: body);

  Future<dynamic> delete(String path) => request('DELETE', path);
}
