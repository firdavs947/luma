import 'package:equatable/equatable.dart';

/// Песня Genius — только то, что нужно интерфейсу приложения.
///
/// Модель неизменяемая: это упрощает сравнение состояний в BLoC
/// и безопасную передачу между экранами.
///
/// Важная особенность Genius: это база текстов песен, поэтому у песни нет
/// ни длительности, ни аудио-превью. Интерфейс приложения остаётся тем же —
/// недостающие значения закрываются безопасными подстановками ниже.
class GeniusSong extends Equatable {
  const GeniusSong({
    required this.id,
    required this.title,
    required this.artistNames,
    this.imageUrl,
    this.url,
    this.releaseYear,
    this.albumId,
    this.albumName,
    this.albumImageUrl,
  });

  /// Создаёт песню из ответа Genius API.
  ///
  /// Подходит и для результатов `/search`, и для песен из
  /// `/artists/{id}/songs`, и для записей `/albums/{id}/tracks` (там песня
  /// лежит внутри элемента под ключом `song`), и для `/songs/{id}` — в
  /// последнем случае дополнительно заполняются поля альбома.
  factory GeniusSong.fromJson(Map<String, dynamic> json) {
    final album = json['album'] as Map<String, dynamic>?;

    return GeniusSong(
      id: json['id']?.toString() ?? '',
      title: _nonEmpty(json['title'] as String?) ?? 'Без названия',
      artistNames: _artistNames(json),
      imageUrl: _nonEmpty(json['song_art_image_url'] as String?) ??
          _nonEmpty(json['header_image_url'] as String?),
      url: _nonEmpty(json['url'] as String?),
      releaseYear: _yearOf(json),
      albumId: album?['id']?.toString(),
      albumName: _nonEmpty(album?['name'] as String?),
      albumImageUrl: _nonEmpty(album?['cover_art_url'] as String?),
    );
  }

  final String id;
  final String title;

  /// Исполнители песни строкой: у Genius это готовое поле `artist_names`.
  final String artistNames;

  /// Обложка песни (у альбомных песен совпадает с обложкой альбома).
  final String? imageUrl;

  /// Ссылка на страницу песни на genius.com.
  final String? url;

  /// Год релиза, если Genius его отдал.
  final int? releaseYear;

  /// Идентификатор альбома — заполняется только в ответе `/songs/{id}`.
  final String? albumId;
  final String? albumName;
  final String? albumImageUrl;

  /// Genius не отдаёт длительность песни, поэтому вместо секунд в интерфейсе
  /// показывается прочерк: строка треклиста и плеер продолжают работать.
  String get durationLabel => '—';

  bool get hasAlbum => albumId != null && albumId!.isNotEmpty;

  @override
  List<Object?> get props => [id, title, artistNames, imageUrl];
}

/// Альбом Genius вместе с треками.
///
/// В выдаче `/search` и `/artists/{id}/songs` альбомов нет — Genius
/// песне-центричный сервис. Альбом собирается двумя запросами:
/// `/songs/{id}` (идентификатор альбома) и `/albums/{id}/tracks` (треки).
class GeniusAlbum extends Equatable {
  const GeniusAlbum({
    required this.id,
    required this.name,
    required this.artistNames,
    required this.albumType,
    this.releaseDate,
    this.coverArtUrl,
    this.tracks = const [],
  });

  /// Создаёт альбом из ответа `/albums/{id}`.
  factory GeniusAlbum.fromJson(
    Map<String, dynamic> json, {
    List<GeniusSong> tracks = const [],
  }) {
    final artist = json['artist'] as Map<String, dynamic>?;

    return GeniusAlbum(
      id: json['id']?.toString() ?? '',
      name: _nonEmpty(json['name'] as String?) ??
          _nonEmpty(json['full_title'] as String?) ??
          'Без названия',
      artistNames: _joinArtists(json['primary_artists']) ??
          _nonEmpty(artist?['name'] as String?) ??
          'Неизвестный исполнитель',
      albumType: _nonEmpty(json['album_type'] as String?) ?? 'album',
      releaseDate: _nonEmpty(json['release_date_for_display'] as String?) ??
          _nonEmpty(json['release_date'] as String?),
      coverArtUrl: _nonEmpty(json['cover_art_url'] as String?),
      tracks: tracks,
    );
  }

  final String id;
  final String name;
  final String artistNames;

  /// Тип релиза: `album`, `single`, `ep`, `compilation`.
  final String albumType;

  /// Дата релиза в формате Genius: `June 12, 2008`.
  final String? releaseDate;
  final String? coverArtUrl;
  final List<GeniusSong> tracks;

  /// Год релиза для подписи под названием.
  String? get releaseYear {
    final date = releaseDate;
    if (date == null) return null;
    final match = RegExp(r'\d{4}').firstMatch(date);
    return match?.group(0);
  }

  /// Человекочитаемая подпись типа релиза.
  String get typeLabel => switch (albumType) {
        'single' => 'Сингл',
        'ep' => 'Мини-альбом',
        'compilation' => 'Сборник',
        _ => 'Альбом',
      };

  int get totalTracks => tracks.length;

  @override
  List<Object?> get props => [id, name, artistNames, albumType, coverArtUrl, tracks];
}

/// Музыкальная подборка Genius.
///
/// Сводит альбом к одной форме, поэтому экран треклиста не знает, что именно
/// вернул источник, и остаётся неизменным при смене бэкенда.
class MusicCollection extends Equatable {
  const MusicCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.typeLabel,
    required this.tracks,
    this.releaseYear,
    this.imageUrl,
    this.description = '',
  });

  factory MusicCollection.fromAlbum(GeniusAlbum album) => MusicCollection(
        id: album.id,
        title: album.name,
        subtitle: album.artistNames,
        typeLabel: album.typeLabel,
        tracks: album.tracks,
        releaseYear: album.releaseYear,
        imageUrl: album.coverArtUrl,
        description: album.artistNames,
      );

  final String id;
  final String title;

  /// Исполнитель альбома.
  final String subtitle;

  /// «Альбом», «Сингл», «Мини-альбом» или «Сборник».
  final String typeLabel;
  final List<GeniusSong> tracks;
  final String? releaseYear;
  final String? imageUrl;
  final String description;

  int get totalTracks => tracks.length;

  @override
  List<Object?> get props => [id, title, typeLabel, tracks];
}

/// Имена исполнителей: сначала `artist_names`, затем запасные поля.
String _artistNames(Map<String, dynamic> json) {
  return _nonEmpty(json['artist_names'] as String?) ??
      _nonEmpty(json['primary_artist_names'] as String?) ??
      _joinArtists(json['primary_artists']) ??
      'Неизвестный исполнитель';
}

/// Собирает имена исполнителей из массива объектов.
String? _joinArtists(dynamic artistsJson) {
  if (artistsJson is! List) return null;
  final names = artistsJson
      .whereType<Map<String, dynamic>>()
      .map((artist) => artist['name'] as String? ?? '')
      .where((name) => name.isNotEmpty)
      .join(', ');
  return names.isEmpty ? null : names;
}

/// Достаёт год релиза: сначала из структурной даты, затем из строки.
int? _yearOf(Map<String, dynamic> json) {
  final components = json['release_date_components'] as Map<String, dynamic>?;
  final year = (components?['year'] as num?)?.toInt();
  if (year != null) return year;

  final display = json['release_date_for_display'] as String?;
  if (display == null) return null;
  final match = RegExp(r'\d{4}').firstMatch(display);
  return match == null ? null : int.tryParse(match.group(0)!);
}

/// Возвращает строку или `null`, если она пустая.
String? _nonEmpty(String? value) =>
    (value == null || value.isEmpty) ? null : value;
