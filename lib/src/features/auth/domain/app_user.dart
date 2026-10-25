import 'package:flutter/foundation.dart';

/// Пользователь сервиса LUMA.
///
/// Хранит только те данные, которые необходимы интерфейсу; пароль в модель
/// никогда не попадает — в хранилище остаётся лишь хеш учётных данных.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.memberSince,
    this.plan = 'LUMA Premium',
    this.avatarSeed = 0,
  });

  final String id;
  final String name;
  final String email;
  final DateTime memberSince;
  final String plan;
  final int avatarSeed;

  /// Инициалы для аватара.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'L';
    final first = parts.first.substring(0, 1).toUpperCase();
    if (parts.length == 1) return first;
    final last = parts.last.substring(0, 1).toUpperCase();
    return '$first$last';
  }

  AppUser copyWith({String? name, String? email, String? plan}) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      memberSince: memberSince,
      plan: plan ?? this.plan,
      avatarSeed: avatarSeed,
    );
  }

  /// Сериализация в локальное хранилище (пароли не сохраняются).
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'memberSince': memberSince.toIso8601String(),
        'plan': plan,
        'avatarSeed': avatarSeed,
      };

  static AppUser fromJson(Map<String, Object?> json) {
    return AppUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      memberSince: DateTime.tryParse(
            json['memberSince'] as String? ?? '',
          ) ??
          DateTime.now(),
      plan: json['plan'] as String? ?? 'LUMA Premium',
      avatarSeed: (json['avatarSeed'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
