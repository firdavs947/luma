import 'package:flutter/foundation.dart';

/// Запись, которую может проиграть аудиоплеер.
///
/// Резолвер отдаёт не только ссылку, но и то, откуда она пришла, и полная
/// это песня или короткий ознакомительный фрагмент — плееру это нужно,
/// чтобы честно подписать происходящее на экране.
@immutable
class ResolvedTrackStream {
  const ResolvedTrackStream({
    required this.url,
    required this.source,
    required this.isFullLength,
  });

  /// Прямая ссылка на аудио: её понимает аудиоплеер без доп. логики.
  final String url;

  /// Провайдер, отдавший запись: «Audius», «Apple Music», «Deezer».
  final String source;

  /// Полная песня, а не короткий ознакомительный фрагмент.
  final bool isFullLength;

  @override
  String toString() =>
      'ResolvedTrackStream($source, fullLength: $isFullLength, $url)';
}

/// Ищет воспроизводимый звук по названию и исполнителю.
///
/// Источник метаданных (Genius) — база текстов песен: он отдаёт названия,
/// исполнителей и обложки, но не аудио. Поэтому плеер спрашивает резолвер,
/// а тот подбирает запись в каталогах, которые действительно транслируют
/// звук. Реализация по умолчанию — `StreamingTrackResolver`.
abstract interface class TrackStreamResolver {
  /// Возвращает запись или `null`, если подходящей не нашлось.
  Future<ResolvedTrackStream?> resolve({
    required String title,
    required String artist,
  });
}
