
import 'package:flutter/material.dart';

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
  int selectedTab = 0;

  final List<String> categories = [
    'الكل',
    'أكشن',
    'دراما',
    'كوميديا',
    'رعب',
    'خيال علمي',
  ];

  int selectedCategory = 0;

  final List<Map<String, dynamic>> movies = [
    {'title': 'فيلم الأكشن', 'type': 'أكشن', 'icon': Icons.movie},
    {'title': 'رحلة الغموض', 'type': 'غموض', 'icon': Icons.theater_comedy},
    {'title': 'عالم الخيال', 'type': 'خيال علمي', 'icon': Icons.rocket},
    {'title': 'قصة حب', 'type': 'دراما', 'icon': Icons.favorite},
  ];

  final List<String> channels = [
    'قناة الأخبار',
    'قناة الرياضة',
    'قناة الأفلام',
    'قناة المسلسلات',
  ];

  Widget movieCard(Map<String, dynamic> movie) {
    return Container(
      width: 135,
      margin: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 175,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF493B25), Color(0xFF151515)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Icon(
                movie['icon'] as IconData,
                color: gold,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            movie['title'] as String,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            movie['type'] as String,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
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

  Widget homeContent() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
          child: Row(
            children: [
              const Icon(Icons.movie_filter, color: gold, size: 32),
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
                    delegate: MovieSearch(),
                  );
                },
                icon: const Icon(Icons.search, color: Colors.white),
              ),
              const Icon(Icons.notifications_none, color: gold),
            ],
          ),
        ),

        // Featured movie
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF604821), Color(0xFF211A10), panel],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('سيتم تفعيل المشاهدة قريباً'),
                            ),
                          );
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final active = selectedCategory == index;
              return GestureDetector(
                onTap: () => setState(() => selectedCategory = index),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: active ? gold : panel,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    categories[index],
                    style: TextStyle(
                      color: active ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        sectionTitle('أحدث الأفلام'),

        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: movies.map(movieCard).toList(),
          ),
        ),

        sectionTitle('القنوات المباشرة'),

        ...channels.map((channel) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF342B1D),
                child: Icon(Icons.live_tv, color: gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Icon(Icons.circle, color: Colors.red, size: 9),
              const SizedBox(width: 6),
              const Text(
                'مباشر',
                style: TextStyle(color: gold, fontSize: 12),
              ),
            ],
          ),
        )),

        const SizedBox(height: 30),
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
      otherPage('الأفلام', Icons.movie),
      otherPage('المسلسلات', Icons.video_library),
      otherPage('البث المباشر', Icons.live_tv),
      otherPage('المفضلة', Icons.favorite),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(child: pages[selectedTab]),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF151515),
          indicatorColor: const Color(0xFF493B25),
          selectedIndex: selectedTab,
          onDestinationSelected: (index) {
            setState(() => selectedTab = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: gold),
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
  @override
  String get searchFieldLabel => 'ابحث عن فيلم أو مسلسل';

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      onPressed: () => query = '',
      icon: const Icon(Icons.clear),
    ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => Center(
    child: Text(
      'نتائج البحث عن: $query',
      style: const TextStyle(color: Colors.white),
    ),
  );

  @override
  Widget buildSuggestions(BuildContext context) => const Center(
    child: Text(
      'اكتب اسم الفيلم أو المسلسل',
      style: TextStyle(color: Colors.white54),
    ),
  );
}