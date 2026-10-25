import '../domain/media_item.dart';
import '../domain/music_source.dart';
import 'mock_catalog.dart';

/// Локальный источник музыки.
///
/// Используется как фолбэк: если Genius не настроен или недоступен,
/// приложение продолжает работать на демонстрационном наборе.
class MockMusicSource implements MusicSource {
  const MockMusicSource();

  /// Размер страницы выдачи: совпадает с размером страницы источника,
  /// чтобы кнопка «Показать ещё» вела себя одинаково в обоих режимах.
  static const _pageSize = 20;

  @override
  Future<List<MediaItem>> featured() async => MockCatalog.music;

  @override
  Future<MusicSearchPage> search(String query, {int offset = 0}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return MusicSearchPage.empty;

    final matches = MockCatalog.music
        .where(
          (item) =>
              item.title.toLowerCase().contains(normalized) ||
              item.subtitle.toLowerCase().contains(normalized),
        )
        .toList();

    if (offset >= matches.length) return MusicSearchPage.empty;

    final end = (offset + _pageSize).clamp(0, matches.length);
    return MusicSearchPage(
      items: matches.sublist(offset, end),
      hasMore: end < matches.length,
    );
  }
}
