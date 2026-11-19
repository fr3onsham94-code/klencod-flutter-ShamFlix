
import 'package:flutter/material.dart';
import 'tmdb_service.dart';

void main() {
  runApp(const ShamFlixApp());
}

const bg = Color(0xFF090909);
const gold = Color(0xFFD6AC55);
const panel = Color(0xFF191919);

class ShamFlixApp extends StatelessWidget {
  const ShamFlixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ShamFlix',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: panel,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TmdbService tmdb = TmdbService();

  int selectedTab = 0;
  int selectedCategory = 0;

  late Future<List<dynamic>> popularMovies;
  late Future<List<dynamic>> latestMovies;
  late Future<List<dynamic>> popularTv;

  final List<String> categories = [
    'الكل',
    'أكشن',
    'دراما',
    'كوميديا',
    'رعب',
    'خيال علمي',
  ];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() {
    popularMovies = tmdb.getPopularMovies();
    latestMovies = tmdb.getNowPlayingMovies();
    popularTv = tmdb.getPopularTv();
  }

  void refreshData() {
    setState(() {
      loadData();
    });
  }

  String mediaTitle(Map<String, dynamic> item) {
    return item['title'] ??
        item['name'] ??
        'بدون عنوان';
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            color: gold,
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget movieCard(Map<String, dynamic> movie) {
    final poster = TmdbService.getPoster(
      movie['poster_path'],
    );

    return Container(
      width: 135,
      margin: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 135,
              height: 175,
              child: poster == null
                  ? Container(
                      color: panel,
                      child: const Icon(
                        Icons.movie,
                        color: gold,
                        size: 48,
                      ),
                    )
                  : Image.network(
                      poster,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: panel,
                          child: const Icon(
                            Icons.movie,
                            color: gold,
                            size: 48,
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mediaTitle(movie),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            movie['release_date'] ??
                movie['first_air_date'] ??
                'ShamFlix',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget mediaSection(
    String title,
    Future<List<dynamic>> future,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(title),
        SizedBox(
          height: 220,
          child: FutureBuilder<List<dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: gold,
                  ),
                );
              }

              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'تعذر تحميل البيانات',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }

              final items = snapshot.data ?? [];

              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'لا توجد بيانات حالياً',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return movieCard(
                    Map<String, dynamic>.from(items[index]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget homeContent() {
    return RefreshIndicator(
      color: gold,
      backgroundColor: panel,
      onRefresh: () async {
        refreshData();
      },
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              18, 15, 18, 15,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.movie_filter,
                  color: gold,
                  size: 32,
                ),
                const SizedBox(width: 9),
                const Text(
                  'Sham',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Flix',
                  style: TextStyle(
                    color: gold,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    showSearch(
                      context: context,
                      delegate: MovieSearch(tmdb),
                    );
                  },
                  icon: const Icon(
                    Icons.search,
                    color: Colors.white,
                  ),
                ),
                const Icon(
                  Icons.notifications_none,
                  color: gold,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF604821),
                    Color(0xFF211A10),
                    panel,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: 20,
                    top: 30,
                    child: Icon(
                      Icons.local_movies,
                      color: Color(0x44FFFFFF),
                      size: 130,
                    ),
                  ),
                  Positioned(
                    right: 18,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ShamFlix ORIGINAL',
                          style: TextStyle(
                            color: gold,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'اكتشف عالم السينما',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: gold,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () {
                            setState(() {
                              selectedTab = 1;
                            });
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('استكشف الآن'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          sectionTitle('التصنيفات'),

          SizedBox(
            height: 43,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final active = selectedCategory == index;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedCategory = index;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                    ),
                    decoration: BoxDecoration(
                      color: active ? gold : panel,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      categories[index],
                      style: TextStyle(
                        color: active
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          mediaSection(
            'أحدث الأفلام',
            latestMovies,
          ),

          mediaSection(
            'الأفلام الأكثر شعبية',
            popularMovies,
          ),

          mediaSection(
            'المسلسلات الأكثر شعبية',
            popularTv,
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget moviesPage() {
    return ListView(
      children: [
        sectionTitle('أحدث الأفلام'),
        mediaSection('الأفلام الجديدة', latestMovies),
        mediaSection('الأكثر شعبية', popularMovies),
      ],
    );
  }

  Widget tvPage() {
    return ListView(
      children: [
        mediaSection('المسلسلات الأكثر شعبية', popularTv),
      ],
    );
  }

  Widget otherPage(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: gold, size: 65),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'سيتم تجهيز هذا القسم قريباً',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeContent(),
      moviesPage(),
      tvPage(),
      otherPage('البث المباشر', Icons.live_tv),
      otherPage('المفضلة', Icons.favorite),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: pages[selectedTab],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF151515),
          indicatorColor: const Color(0xFF493B25),
          selectedIndex: selectedTab,
          onDestinationSelected: (index) {
            setState(() {
              selectedTab = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(
                Icons.home,
                color: gold,
              ),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              label: 'الأفلام',
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              label: 'المسلسلات',
            ),
            NavigationDestination(
              icon: Icon(Icons.live_tv_outlined),
              label: 'مباشر',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              label: 'المفضلة',
            ),
          ],
        ),
      ),
    );
  }
}

class MovieSearch extends SearchDelegate {
  final TmdbService service;

  MovieSearch(this.service);

  @override
  String get searchFieldLabel =>
      'ابحث عن فيلم أو مسلسل';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          query = '';
        },
        icon: const Icon(Icons.clear),
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () {
        close(context, null);
      },
      icon: const Icon(Icons.arrow_back),
    );
  }

  Widget searchResults() {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text(
          'اكتب اسم الفيلم أو المسلسل',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: service.searchMulti(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'حدث خطأ أثناء البحث',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final results = snapshot.data ?? [];

        if (results.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد نتائج',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item =
                Map<String, dynamic>.from(results[index]);

            final poster = TmdbService.getPoster(
              item['poster_path'],
            );

            return ListTile(
              leading: poster == null
                  ? const Icon(Icons.movie, color: gold)
                  : Image.network(
                      poster,
                      width: 45,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const Icon(
                          Icons.movie,
                          color: gold,
                        );
                      },
                    ),
              title: Text(
                item['title'] ??
                    item['name'] ??
                    'بدون عنوان',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                item['media_type'] == 'tv'
                    ? 'مسلسل'
                    : item['media_type'] == 'movie'
                        ? 'فيلم'
                        : 'محتوى',
                style: const TextStyle(color: gold),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return searchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return searchResults();
  }
}
