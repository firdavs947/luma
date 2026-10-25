import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

/// Локальная реализация репозитория аутентификации.
///
/// Используется для демонстрации и тестирования интерфейса без серверной
/// части. Пароли не хранятся в открытом виде: сохраняется только
/// соль и производный хеш (SHA-256, многократное применение).
///
/// ВАЖНО: для публикации в сторах аутентификацию следует выполнять на
/// сервере, а на устройстве держать лишь токен в защищённом хранилище
/// (`flutter_secure_storage` / Keychain / Keystore).
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({this.latency = const Duration(milliseconds: 700)});

  /// Искусственная задержка, имитирующая сетевой запрос.
  final Duration latency;

  static const _accountsKey = 'luma.accounts';
  static const _sessionKey = 'luma.session.user';
  static const _resetKey = 'luma.reset.challenge';
  static const _hashRounds = 1200;

  final _random = Random.secure();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<AppUser?> restoreSession() async {
    await Future<void>.delayed(latency ~/ 3);
    final prefs = await _prefs;
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      await prefs.remove(_sessionKey);
      return null;
    }
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _readAccounts();

    final record = accounts.firstWhere(
      (item) => (item['email'] as String) == normalizedEmail,
      orElse: () => const {},
    );

    // Одинаковый ответ для несуществующего пользователя и неверного пароля
    // исключает перечисление аккаунтов.
    if (record.isEmpty ||
        _hash(password, record['salt'] as String) != record['hash']) {
      throw const AuthFailure(AuthErrorCode.invalidCredentials);
    }

    final user = _userFromRecord(record);
    await _persistSession(user);
    return user;
  }

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _readAccounts();

    final exists = accounts.any(
      (item) => (item['email'] as String) == normalizedEmail,
    );
    if (exists) {
      throw const AuthFailure(AuthErrorCode.emailAlreadyInUse);
    }

    final salt = _generateSalt();
    final record = <String, Object?>{
      'id': 'usr_${DateTime.now().microsecondsSinceEpoch}',
      'name': name.trim(),
      'email': normalizedEmail,
      'salt': salt,
      'hash': _hash(password, salt),
      'memberSince': DateTime.now().toIso8601String(),
      'plan': 'LUMA Premium',
      'avatarSeed': _random.nextInt(1 << 20),
    };

    accounts.add(record);
    final prefs = await _prefs;
    await prefs.setString(_accountsKey, jsonEncode(accounts));

    final user = _userFromRecord(record);
    await _persistSession(user);
    return user;
  }

  @override
  Future<PasswordResetChallenge> requestPasswordReset({
    required String email,
  }) async {
    await Future<void>.delayed(latency);
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _readAccounts();
    final exists = accounts.any(
      (item) => (item['email'] as String) == normalizedEmail,
    );
    if (!exists) {
      throw const AuthFailure(AuthErrorCode.userNotFound);
    }

    final code = List.generate(6, (_) => _random.nextInt(10)).join();
    final prefs = await _prefs;
    await prefs.setString(
      _resetKey,
      jsonEncode({
        'email': normalizedEmail,
        'code': code,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      }),
    );

    return PasswordResetChallenge(
      email: normalizedEmail,
      maskedEmail: _maskEmail(normalizedEmail),
      debugCode: kDebugMode ? code : null,
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await Future<void>.delayed(latency);
    final prefs = await _prefs;
    final raw = prefs.getString(_resetKey);
    if (raw == null) {
      throw const AuthFailure(AuthErrorCode.invalidResetCode);
    }

    final challenge = jsonDecode(raw) as Map<String, Object?>;
    final expiresAt =
        DateTime.tryParse(challenge['expiresAt'] as String? ?? '');
    final isValid = challenge['email'] == email.trim().toLowerCase() &&
        challenge['code'] == code.trim() &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now());

    if (!isValid) {
      throw const AuthFailure(AuthErrorCode.invalidResetCode);
    }

    final accounts = await _readAccounts();
    final index = accounts.indexWhere(
      (item) => (item['email'] as String) == email.trim().toLowerCase(),
    );
    if (index == -1) {
      throw const AuthFailure(AuthErrorCode.userNotFound);
    }

    final salt = _generateSalt();
    accounts[index]['salt'] = salt;
    accounts[index]['hash'] = _hash(newPassword, salt);

    await prefs.setString(_accountsKey, jsonEncode(accounts));
    await prefs.remove(_resetKey);
  }

  @override
  Future<void> signOut() async {
    final prefs = await _prefs;
    await prefs.remove(_sessionKey);
  }

  @override
  Future<AppUser> updateProfile({required String name}) async {
    await Future<void>.delayed(latency ~/ 2);
    final prefs = await _prefs;
    final raw = prefs.getString(_sessionKey);
    if (raw == null) {
      throw const AuthFailure(AuthErrorCode.userNotFound);
    }

    final user = AppUser.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    ).copyWith(name: name.trim());

    await _persistSession(user);

    final accounts = await _readAccounts();
    final index = accounts.indexWhere(
      (item) => (item['email'] as String) == user.email,
    );
    if (index != -1) {
      accounts[index]['name'] = user.name;
      await prefs.setString(_accountsKey, jsonEncode(accounts));
    }
    return user;
  }

  // --- Внутренние помощники -------------------------------------------------

  Future<void> _persistSession(AppUser user) async {
    final prefs = await _prefs;
    await prefs.setString(_sessionKey, jsonEncode(user.toJson()));
  }

  Future<List<Map<String, Object?>>> _readAccounts() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_accountsKey);

    if (raw == null) {
      final seeded = [_seedDemoAccount()];
      await prefs.setString(_accountsKey, jsonEncode(seeded));
      return seeded;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
  }

  /// Демонстрационный аккаунт, доступный сразу после установки.
  Map<String, Object?> _seedDemoAccount() {
    const email = 'demo@luma.app';
    final salt = _generateSalt();
    return {
      'id': 'usr_demo',
      'name': 'LUMA Demo',
      'email': email,
      'salt': salt,
      'hash': _hash('Luma2026', salt),
      'memberSince': DateTime(2026, 1, 12).toIso8601String(),
      'plan': 'LUMA Premium',
      'avatarSeed': 481516,
    };
  }

  AppUser _userFromRecord(Map<String, Object?> record) {
    return AppUser(
      id: record['id'] as String,
      name: record['name'] as String,
      email: record['email'] as String,
      memberSince: DateTime.tryParse(
            record['memberSince'] as String? ?? '',
          ) ??
          DateTime.now(),
      plan: record['plan'] as String? ?? 'LUMA Premium',
      avatarSeed: (record['avatarSeed'] as num?)?.toInt() ?? 0,
    );
  }

  String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Многократное хеширование с солью (упрощённый аналог PBKDF).
  String _hash(String password, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$password'));
    for (var i = 0; i < _hashRounds; i++) {
      digest = sha256.convert([...digest.bytes, ...utf8.encode(salt)]);
    }
    return digest.toString();
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts.first;
    final domain = parts.last;
    final visibleName = name.length <= 2 ? name : name.substring(0, 2);
    final visibleDomain = domain.length <= 2 ? domain : domain.substring(0, 2);
    return '$visibleName••@$visibleDomain••';
  }
}
