import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.provider,
  });

  final String id;
  final String displayName;
  final String email;
  final String provider;

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      id: '${json['id'] ?? json['userId'] ?? ''}',
      displayName:
          '${json['displayName'] ?? json['name'] ?? json['email'] ?? '用户'}',
      email: '${json['email'] ?? ''}',
      provider: '${json['provider'] ?? 'email'}',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'provider': provider,
      };
}

class AccountService extends ChangeNotifier {
  AccountService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            contentType: Headers.jsonContentType,
          ),
        );

  static const _apiBaseUrl = String.fromEnvironment('AUTH_API_BASE_URL');
  static const _tokenKey = 'account.access_token';
  static const _profileKey = 'account.profile';

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AccountProfile? profile;
  bool loading = false;
  bool initialized = false;

  bool get signedIn => profile != null;
  bool get backendConfigured => _apiBaseUrl.trim().isNotEmpty;

  Future<void> initialize() async {
    if (initialized) return;
    try {
      final raw = await _storage.read(key: _profileKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          profile = AccountProfile.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } catch (_) {
      await _storage.delete(key: _profileKey);
      await _storage.delete(key: _tokenKey);
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> signInWithApple() async {
    _requireBackend();
    await _run(() async {
      final available = await SignInWithApple.isAvailable();
      if (!available) {
        throw const AccountException('此设备暂不支持“通过 Apple 登录”');
      }
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final identityToken = credential.identityToken ?? '';
      final authorizationCode = credential.authorizationCode;
      if (identityToken.isEmpty || authorizationCode.isEmpty) {
        throw const AccountException('Apple 没有返回有效登录凭证');
      }
      await _authenticate(
        '/v1/auth/apple',
        {
          'identityToken': identityToken,
          'authorizationCode': authorizationCode,
          'userIdentifier': credential.userIdentifier,
          'email': credential.email,
          'givenName': credential.givenName,
          'familyName': credential.familyName,
        },
      );
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _run(
      () => _authenticate(
        '/v1/auth/login',
        {'email': email.trim(), 'password': password},
      ),
    );
  }

  Future<void> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) {
    return _run(
      () => _authenticate(
        '/v1/auth/register',
        {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
        },
      ),
    );
  }

  Future<void> signOut() async {
    profile = null;
    await Future.wait([
      _storage.delete(key: _profileKey),
      _storage.delete(key: _tokenKey),
    ]);
    notifyListeners();
  }

  Future<void> _authenticate(
    String path,
    Map<String, dynamic> payload,
  ) async {
    _requireBackend();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: payload,
      );
      final body = response.data ?? const <String, dynamic>{};
      final token = '${body['accessToken'] ?? body['token'] ?? ''}';
      final rawUser = body['user'];
      if (token.isEmpty || rawUser is! Map) {
        throw const AccountException('登录服务返回的数据不完整');
      }
      final nextProfile = AccountProfile.fromJson(
        Map<String, dynamic>.from(rawUser),
      );
      await Future.wait([
        _storage.write(key: _tokenKey, value: token),
        _storage.write(
          key: _profileKey,
          value: jsonEncode(nextProfile.toJson()),
        ),
      ]);
      profile = nextProfile;
    } on DioException catch (error) {
      final data = error.response?.data;
      final message = data is Map
          ? '${data['message'] ?? data['error'] ?? ''}'.trim()
          : '';
      throw AccountException(
        message.isEmpty ? '无法连接登录服务，请稍后重试' : message,
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      await action();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _requireBackend() {
    if (!backendConfigured) {
      throw const AccountException(
        '登录服务器尚未配置。发布构建需设置 AUTH_API_BASE_URL。',
      );
    }
  }
}

class AccountException implements Exception {
  const AccountException(this.message);

  final String message;

  @override
  String toString() => message;
}
