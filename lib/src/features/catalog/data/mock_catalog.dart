import '../domain/media_item.dart';

/// Демонстрационный каталог LUMA.
///
/// Названия и описания вымышлены и созданы специально для этого проекта,
/// чтобы не нарушать авторские права третьих лиц.
abstract final class MockCatalog {
  /// Обложки демонстрационных треков.
  ///
  /// В обычном режиме картинки приходят из Genius. Здесь они нужны, чтобы
  /// фолбэк выглядел как настоящая музыкальная библиотека, а не как набор
  /// пустых заглушек: без них пользователь видел только процедурные
  /// подложки и решал, что «обложки не загружаются».
  static const _coverHost =
      'https://coresg-normal.trae.ai/api/ide/v1/text_to_image'
      '?image_size=square_hd&prompt=';

  static const List<MediaItem> music = [
    MediaItem(
      id: 'm1',
      title: 'Neon Tide',
      subtitle: 'Astral Youth',
      category: MediaCategory.music,
      year: 2026,
      durationLabel: '3:42',
      rating: 4.8,
      description:
          'Синтезаторный сингл о ночном городе, где каждый неоновый блик '
          'превращается в отдельную историю.',
      progress: 0.35,
      imageUrl: '$_coverHost neon%20synthwave%20album%20cover%20night%20city'
          '%20purple%20cyan%20glow%20minimal',
    ),
    MediaItem(
      id: 'm2',
      title: 'Velvet Static',
      subtitle: 'Mira Lune',
      category: MediaCategory.music,
      year: 2025,
      durationLabel: '4:08',
      rating: 4.6,
      description:
          'Тёплый лоу-фай с виниловым шумом и мягким вокалом для позднего '
          'вечера.',
      imageUrl: '$_coverHost lo-fi%20chill%20album%20cover%20warm%20sunset'
          '%20window%20vinyl%20texture',
    ),
    MediaItem(
      id: 'm3',
      title: 'Gravity Bloom',
      subtitle: 'Solar Kite',
      category: MediaCategory.music,
      year: 2026,
      durationLabel: '3:11',
      rating: 4.9,
      description: 'Эйфоричный инди-поп с плотным басом и широкими хорами.',
      imageUrl: '$_coverHost indie%20pop%20album%20cover%20colorful%20balloons'
          '%20pastel%20sky',
    ),
    MediaItem(
      id: 'm4',
      title: 'Paper Comet',
      subtitle: 'Nova Ensemble',
      category: MediaCategory.music,
      year: 2024,
      durationLabel: '5:26',
      rating: 4.4,
      description: 'Кинематографичная инструментальная пьеса для трейлеров.',
      imageUrl: '$_coverHost cinematic%20orchestral%20album%20cover%20dark'
          '%20clouds%20light%20beam%20dramatic',
    ),
    MediaItem(
      id: 'm5',
      title: 'Midnight Circuit',
      subtitle: 'Kaito Renn',
      category: MediaCategory.music,
      year: 2025,
      durationLabel: '3:57',
      rating: 4.7,
      description: 'Ретро-футуризм: аналоговые синтезаторы и цифровой ритм.',
      isFavorite: true,
      imageUrl: '$_coverHost retro%20futurism%20album%20cover%20analog'
          '%20synthesizer%20grid%20horizon',
    ),
    MediaItem(
      id: 'm6',
      title: 'Hollow Light',
      subtitle: 'Sable Choir',
      category: MediaCategory.music,
      year: 2026,
      durationLabel: '4:33',
      rating: 4.5,
      description: 'Хоровой эмбиент, записанный в заброшенном кинозале.',
      imageUrl: '$_coverHost ambient%20choir%20album%20cover%20empty%20hall'
          '%20soft%20light',
    ),
    MediaItem(
      id: 'm7',
      title: 'Blue Note Alley',
      subtitle: 'The Copper Quartet',
      category: MediaCategory.music,
      year: 2025,
      durationLabel: '6:12',
      rating: 4.7,
      description: 'Ночная джазовая сессия с саксофоном и контрабасом.',
      imageUrl: '$_coverHost jazz%20album%20cover%20saxophone%20smoky%20club'
          '%20warm%20light',
    ),
    MediaItem(
      id: 'm8',
      title: 'Concrete Skyline',
      subtitle: 'Rook',
      category: MediaCategory.music,
      year: 2026,
      durationLabel: '3:28',
      rating: 4.6,
      description: 'Хип-хоп о городе, который никогда не спит.',
      imageUrl: '$_coverHost hip%20hop%20album%20cover%20urban%20rooftop'
          '%20night%20city%20lights',
    ),
    MediaItem(
      id: 'm9',
      title: 'Static Cathedral',
      subtitle: 'Iron Meadow',
      category: MediaCategory.music,
      year: 2024,
      durationLabel: '4:51',
      rating: 4.5,
      description: 'Гитарный рок с широкими припевами и живыми барабанами.',
      imageUrl: '$_coverHost rock%20album%20cover%20electric%20guitar'
          '%20silhouette%20stage%20lights',
    ),
    MediaItem(
      id: 'm10',
      title: 'Pulse Geometry',
      subtitle: 'Vela',
      category: MediaCategory.music,
      year: 2026,
      durationLabel: '3:36',
      rating: 4.8,
      description: 'Танцевальный трек с плотным басом и ломаным ритмом.',
      imageUrl: '$_coverHost electronic%20dance%20album%20cover%20abstract'
          '%20geometry%20neon',
    ),
    MediaItem(
      id: 'm11',
      title: 'Nocturne in Glass',
      subtitle: 'Anna Weiss',
      category: MediaCategory.music,
      year: 2023,
      durationLabel: '5:04',
      rating: 4.9,
      description: 'Фортепианная миниатюра, записанная в один дубль.',
      imageUrl: '$_coverHost classical%20piano%20album%20cover%20grand%20piano'
          '%20minimal%20white',
    ),
    MediaItem(
      id: 'm12',
      title: 'Saltwater Dream',
      subtitle: 'Coastline',
      category: MediaCategory.music,
      year: 2025,
      durationLabel: '4:17',
      rating: 4.6,
      description: 'Дрим-поп с мягкими гитарами и тёплым аналоговым эхом.',
      imageUrl: '$_coverHost dream%20pop%20album%20cover%20ocean%20waves'
          '%20pastel%20gradient',
    ),
  ];

  static const List<MediaItem> movies = [
    MediaItem(
      id: 'f1',
      title: 'Орбита Молчания',
      subtitle: 'Реж. А. Ветров',
      category: MediaCategory.movies,
      year: 2026,
      durationLabel: '2ч 12м',
      rating: 4.7,
      description:
          'Экипаж исследовательской станции теряет связь с Землёй и '
          'обнаруживает, что тишина тоже может быть сигналом.',
      progress: 0.2,
    ),
    MediaItem(
      id: 'f2',
      title: 'Стальные Сады',
      subtitle: 'Реж. Л. Марчук',
      category: MediaCategory.movies,
      year: 2025,
      durationLabel: '1ч 58м',
      rating: 4.5,
      description:
          'В городе, где растения выращивают на заводах, ботаник находит '
          'настоящее семя.',
    ),
    MediaItem(
      id: 'f3',
      title: 'Последний Сеанс',
      subtitle: 'Реж. И. Ковач',
      category: MediaCategory.movies,
      year: 2024,
      durationLabel: '1ч 44м',
      rating: 4.3,
      description: 'Драма о киномеханике, который спасает плёнку от огня.',
    ),
    MediaItem(
      id: 'f4',
      title: 'Глубина 7',
      subtitle: 'Реж. Р. Салимов',
      category: MediaCategory.movies,
      year: 2026,
      durationLabel: '2ч 05м',
      rating: 4.6,
      description: 'Клаустрофобный триллер о подводной экспедиции.',
      isFavorite: true,
    ),
    MediaItem(
      id: 'f5',
      title: 'Стеклянный Дождь',
      subtitle: 'Реж. Н. Белова',
      category: MediaCategory.movies,
      year: 2025,
      durationLabel: '1ч 51м',
      rating: 4.2,
      description: 'Мелодрама о городе, где дождь звенит как стекло.',
    ),
    MediaItem(
      id: 'f6',
      title: 'Код Миража',
      subtitle: 'Реж. Т. Ахмад',
      category: MediaCategory.movies,
      year: 2026,
      durationLabel: '2ч 18м',
      rating: 4.8,
      description: 'Научная фантастика о художниках, которые рисуют будущее.',
    ),
  ];

  static const List<MediaItem> anime = [
    MediaItem(
      id: 'a1',
      title: 'Хроники Аяка',
      subtitle: '12 эпизодов',
      category: MediaCategory.anime,
      year: 2026,
      durationLabel: '24м/эп',
      rating: 4.9,
      description:
          'Юная картограф путешествует по плавающим островам и рисует '
          'невозможные маршруты.',
      progress: 0.5,
    ),
    MediaItem(
      id: 'a2',
      title: 'Клинок Рассвета',
      subtitle: '24 эпизода',
      category: MediaCategory.anime,
      year: 2025,
      durationLabel: '24м/эп',
      rating: 4.7,
      description: 'Дуэли мастеров меча под аккомпанемент весеннего дождя.',
    ),
    MediaItem(
      id: 'a3',
      title: 'Небесный Почтамт',
      subtitle: '10 эпизодов',
      category: MediaCategory.anime,
      year: 2026,
      durationLabel: '23м/эп',
      rating: 4.6,
      description: 'Тёплая история о курьерах, доставляющих письма в облака.',
      isFavorite: true,
    ),
    MediaItem(
      id: 'a4',
      title: 'Парящие Библиотеки',
      subtitle: '13 эпизодов',
      category: MediaCategory.anime,
      year: 2024,
      durationLabel: '25м/эп',
      rating: 4.4,
      description: 'Магия книг, которые выбирают своих читателей.',
    ),
    MediaItem(
      id: 'a5',
      title: 'Тихий Патруль',
      subtitle: '12 эпизодов',
      category: MediaCategory.anime,
      year: 2025,
      durationLabel: '24м/эп',
      rating: 4.5,
      description: 'Городские стражи следят за порядком между мирами.',
    ),
    MediaItem(
      id: 'a6',
      title: 'Звёздный Пилот',
      subtitle: '26 эпизодов',
      category: MediaCategory.anime,
      year: 2026,
      durationLabel: '24м/эп',
      rating: 4.8,
      description: 'Гонки на солнечных парусах и цена победы.',
    ),
  ];

  static const List<MediaItem> series = [
    MediaItem(
      id: 's1',
      title: 'Северный Протокол',
      subtitle: 'Сезон 2',
      category: MediaCategory.series,
      year: 2026,
      durationLabel: '48м/эп',
      rating: 4.7,
      description:
          'Аналитики раскрывают схему, которая меняет правила мировой '
          'экономики.',
      progress: 0.75,
    ),
    MediaItem(
      id: 's2',
      title: 'Дом на Дюнах',
      subtitle: 'Сезон 1',
      category: MediaCategory.series,
      year: 2025,
      durationLabel: '52м/эп',
      rating: 4.5,
      description: 'Семейная сага о доме, который помнит всех своих жильцов.',
    ),
    MediaItem(
      id: 's3',
      title: 'Тихие Этажи',
      subtitle: 'Сезон 3',
      category: MediaCategory.series,
      year: 2026,
      durationLabel: '45м/эп',
      rating: 4.6,
      description: 'Детектив в небоскрёбе, где каждый этаж — отдельная тайна.',
      isFavorite: true,
    ),
    MediaItem(
      id: 's4',
      title: 'Курс на Восток',
      subtitle: 'Сезон 1',
      category: MediaCategory.series,
      year: 2024,
      durationLabel: '42м/эп',
      rating: 4.3,
      description: 'Приключенческий роуд-муви по забытым железным дорогам.',
    ),
    MediaItem(
      id: 's5',
      title: 'Лаборатория Снов',
      subtitle: 'Сезон 2',
      category: MediaCategory.series,
      year: 2025,
      durationLabel: '50м/эп',
      rating: 4.8,
      description: 'Учёные записывают сны добровольцев и находят чужое.',
    ),
    MediaItem(
      id: 's6',
      title: 'Пятый Редактор',
      subtitle: 'Сезон 1',
      category: MediaCategory.series,
      year: 2026,
      durationLabel: '46м/эп',
      rating: 4.4,
      description: 'Редакция газеты против новостей, которых ещё не было.',
    ),
  ];

  static const List<MediaItem> cartoons = [
    MediaItem(
      id: 'c1',
      title: 'Пушистая Команда',
      subtitle: 'Сезон 1',
      category: MediaCategory.cartoons,
      year: 2026,
      durationLabel: '12м/эп',
      rating: 4.6,
      description: 'Отряд зверят чинит всё, что сломалось в их городке.',
      progress: 0.4,
    ),
    MediaItem(
      id: 'c2',
      title: 'Облачный Мастер',
      subtitle: 'Полнометражный',
      category: MediaCategory.cartoons,
      year: 2025,
      durationLabel: '1ч 28м',
      rating: 4.8,
      description: 'Девочка учится лепить облака и случайно создаёт грозу.',
      isFavorite: true,
    ),
    MediaItem(
      id: 'c3',
      title: 'Робот Бублик',
      subtitle: 'Сезон 2',
      category: MediaCategory.cartoons,
      year: 2026,
      durationLabel: '11м/эп',
      rating: 4.5,
      description: 'Маленький робот-пекарь спасает кондитерскую.',
    ),
    MediaItem(
      id: 'c4',
      title: 'Лесные Письма',
      subtitle: 'Сезон 1',
      category: MediaCategory.cartoons,
      year: 2024,
      durationLabel: '13м/эп',
      rating: 4.4,
      description: 'Медвежонок-почтальон учится дружбе и терпению.',
    ),
    MediaItem(
      id: 'c5',
      title: 'Космо-Котята',
      subtitle: 'Сезон 3',
      category: MediaCategory.cartoons,
      year: 2025,
      durationLabel: '12м/эп',
      rating: 4.7,
      description: 'Котята исследуют дальние планеты и возвращаются домой.',
    ),
    MediaItem(
      id: 'c6',
      title: 'Театр Теней',
      subtitle: 'Полнометражный',
      category: MediaCategory.cartoons,
      year: 2026,
      durationLabel: '1ч 15м',
      rating: 4.6,
      description: 'Кукольный спектакль, который оживает по ночам.',
    ),
  ];

  /// Видеоконтент: фильмы, аниме, сериалы и мультфильмы.
  ///
  /// Музыка наполняется источником музыки (Genius либо локальный фолбэк),
  /// поэтому в этот список не входит.
  static const List<MediaItem> video = [
    ...movies,
    ...anime,
    ...series,
    ...cartoons,
  ];

  /// Полный список демонстрационного контента.
  static const List<MediaItem> all = [
    ...music,
    ...video,
  ];

  /// Контент выбранного раздела.
  static List<MediaItem> byCategory(MediaCategory category) {
    return switch (category) {
      MediaCategory.music => music,
      MediaCategory.movies => movies,
      MediaCategory.anime => anime,
      MediaCategory.series => series,
      MediaCategory.cartoons => cartoons,
    };
  }

  /// Подборка «Смотреть сегодня» для верхнего баннера.
  static const MediaItem featured = MediaItem(
    id: 'featured',
    title: 'Орбита Молчания',
    subtitle: 'Премьера LUMA · Эксклюзив',
    category: MediaCategory.movies,
    year: 2026,
    durationLabel: '2ч 12м',
    rating: 4.7,
    description:
        'Экипаж исследовательской станции теряет связь с Землёй и '
        'обнаруживает, что тишина тоже может быть сигналом. Эксклюзивная '
        'премьера в 4K с пространственным звуком.',
  );

  /// Поиск по каталогу с учётом регистра.
  static List<MediaItem> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return all
        .where(
          (item) =>
              item.title.toLowerCase().contains(normalized) ||
              item.subtitle.toLowerCase().contains(normalized) ||
              item.category.label.toLowerCase().contains(normalized),
        )
        .toList();
  }

  /// Формирует «серверные» рекомендации без дублей.
  static List<MediaItem> recommendationsFor(MediaItem item) {
    return all
        .where((other) =>
            other.id != item.id && other.category == item.category)
        .take(4)
        .toList();
  }
}
