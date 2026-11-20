
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'admin_auth_service.dart';
import 'auth_page.dart';
import 'admin_page.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

final ValueNotifier<int> authRefreshNotifier = ValueNotifier<int>(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AuthService.initialize().timeout(
    const Duration(seconds: 20),
  );

  runApp(const ShamFlixApp());
}

const bg = Color(0xFF090909);
const gold = Color(0xFFD6AC55);
const panel = Color(0xFF191919);

String valueOf(dynamic value, [String fallback = '']) {
  if (value == null || value.toString().trim().isEmpty) {
    return fallback;
  }
  return value.toString();
}

class ShamFlixApp extends StatefulWidget {
  const ShamFlixApp({super.key});

  @override
  State<ShamFlixApp> createState() => _ShamFlixAppState();
}

class _ShamFlixAppState extends State<ShamFlixApp> {
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();

    authSubscription =
        AuthService.client.auth.onAuthStateChange.listen(
      (data) {
        authRefreshNotifier.value++;

        if (data.event == AuthChangeEvent.passwordRecovery) {
          messengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text(
                'تم التحقق من رابط الاستعادة. يمكنك تعيين كلمة مرور جديدة.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
      },
      onError: (error) {
        messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء تحديث حالة الحساب'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
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
  int selectedCategory = 0;

  // إعداد إظهار أو إخفاء شارة التصنيف
  bool showCategoryBadge = true;

  late Future<List<Map<String, dynamic>>> movies;
  late Future<List<Map<String, dynamic>>> series;
  late Future<List<Map<String, dynamic>>> channels;

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
    loadCategoryBadgeSetting();
    authRefreshNotifier.addListener(onAuthChanged);
  }

  // جلب إعداد الشارة من Supabase
  Future<void> loadCategoryBadgeSetting() async {
    try {
      final result = await AuthService.client
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', 'show_category_badge')
          .maybeSingle();

      if (!mounted) return;

      final value = result?['setting_value'];

      setState(() {
        showCategoryBadge = value == null
            ? true
            : value == true ||
                value.toString().toLowerCase() == 'true';
      });
    } catch (_) {
      // في حال فشل الاتصال تبقى الشارة ظاهرة افتراضياً.
    }
  }

  void onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    authRefreshNotifier.removeListener(onAuthChanged);
    super.dispose();
  }

  void loadData() {
    movies = SupabaseService.getMovies();
    series = SupabaseService.getSeries();
    channels = SupabaseService.getChannels();
  }

  Future<void> refreshData() async {
    setState(loadData);

    await Future.wait([
      movies.then((_) {}).catchError((_) {}),
      series.then((_) {}).catchError((_) {}),
      channels.then((_) {}).catchError((_) {}),
    ]);
  }

  List<Map<String, dynamic>> filterCategory(
    List<Map<String, dynamic>> items,
  ) {
    if (selectedCategory == 0) return items;

    final selected = categories[selectedCategory];

    return items.where((item) {
      return valueOf(item['category']) == selected;
    }).toList();
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
      child: Row(
        children: [
          Container(width: 4, height: 22, color: gold),
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

  Widget posterImage(String? url, {double height = 175}) {
    if (url == null || url.isEmpty) {
      return Container(
        height: height,
        color: panel,
        child: const Center(
          child: Icon(Icons.movie, color: gold, size: 48),
        ),
      );
    }

    return Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Container(
          height: height,
          color: panel,
          child: const Center(
            child: Icon(Icons.movie, color: gold, size: 48),
          ),
        );
      },
    );
  }

  void openDetails(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsPage(
          item: item,
          isSeries: isSeries,
        ),
      ),
    );
  }

  Widget mediaCard(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) {
    final poster = valueOf(item['poster_url']);
    final category = valueOf(item['category']);

    return GestureDetector(
      onTap: () => openDetails(item, isSeries: isSeries),
      child: Container(
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    posterImage(poster),

                    if (showCategoryBadge && category.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: gold,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              valueOf(item['title'], 'بدون عنوان'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              valueOf(item['release_year'], 'ShamFlix'),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget mediaSection(
    String title,
    Future<List<Map<String, dynamic>>> future, {
    required bool isSeries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(title),
        SizedBox(
          height: 220,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: gold),
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

              final items = filterCategory(snapshot.data ?? []);

              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'لا يوجد محتوى منشور حالياً',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return mediaCard(
                    items[index],
                    isSeries: isSeries,
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
      onRefresh: refreshData,
      child: ListView(
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
                      delegate: ShamFlixSearch(),
                    );
                  },
                  icon: const Icon(Icons.search, color: Colors.white),
                ),
                const Icon(Icons.notifications_none, color: gold),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
          mediaSection('أحدث الأفلام', movies, isSeries: false),
          mediaSection('المسلسلات', series, isSeries: true),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget moviesPage() {
    return ListView(
      children: [
        mediaSection('الأفلام', movies, isSeries: false),
      ],
    );
  }

  Widget tvPage() {
    return ListView(
      children: [
        mediaSection('المسلسلات', series, isSeries: true),
      ],
    );
  }

  Widget channelsPage() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: channels,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'تعذر تحميل القنوات',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد قنوات منشورة حالياً',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return RefreshIndicator(
          color: gold,
          onRefresh: refreshData,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final channel = items[index];

              return Card(
                color: panel,
                margin: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: bg,
                    backgroundImage:
                        valueOf(channel['logo_url']).isNotEmpty
                            ? NetworkImage(valueOf(channel['logo_url']))
                            : null,
                    child: valueOf(channel['logo_url']).isEmpty
                        ? const Icon(Icons.live_tv, color: gold)
                        : null,
                  ),
                  title: Text(
                    valueOf(channel['name'], 'قناة'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    valueOf(channel['category'], 'بث مباشر'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: const Icon(
                    Icons.play_circle_outline,
                    color: gold,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailsPage(
                          item: channel,
                          isSeries: false,
                          isChannel: true,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeContent(),
      moviesPage(),
      tvPage(),
      channelsPage(),
      const FavoritesPage(),
      const AccountPage(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: selectedTab,
            children: pages,
          ),
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
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: gold),
              label: 'حسابي',
            ),
          ],
        ),
      ),
    );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool loading = false;
  bool linkingGoogle = false;

  @override
  void initState() {
    super.initState();
    authRefreshNotifier.addListener(onAuthChanged);
  }

  @override
  void dispose() {
    authRefreshNotifier.removeListener(onAuthChanged);
    super.dispose();
  }

  void onAuthChanged() {
    if (mounted) setState(() {});
  }

  bool get isGoogleLinked {
    final user = AuthService.client.auth.currentUser;

    if (user == null) return false;

    return user.identities?.any(
          (identity) => identity.provider == 'google',
        ) ??
        false;
  }

  Future<void> openLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthPage(),
      ),
    );

    if (mounted) setState(() {});
  }

  Future<void> linkGoogleAccount() async {
    if (!AuthService.isLoggedIn) {
      showMessage('يرجى تسجيل الدخول أولاً');
      return;
    }

    if (isGoogleLinked) {
      showMessage('حساب Google مربوط بالفعل');
      return;
    }

    setState(() => linkingGoogle = true);

    try {
      await AuthService.linkGoogle();

      if (!mounted) return;

      showMessage(
        'تم فتح صفحة Google. أكمل الموافقة لربط حسابك.',
      );
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => linkingGoogle = false);
      }
    }
  }

  Future<void> logout() async {
    setState(() => loading = true);

    try {
      await AuthService.signOut();

      if (!mounted) return;

      setState(() {});
      showMessage('تم تسجيل الخروج');
    } catch (_) {
      if (!mounted) return;
      showMessage('تعذر تسجيل الخروج');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget accountTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      color: panel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: gold),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: const TextStyle(color: Colors.white54),
              ),
        trailing: const Icon(
          Icons.chevron_left,
          color: gold,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget googleAccountTile() {
    final linked = isGoogleLinked;

    return Card(
      color: panel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(
          Icons.g_mobiledata,
          color: gold,
          size: 32,
        ),
        title: Text(
          linked ? 'حساب Google مربوط' : 'ربط حساب Google',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          linked
              ? 'يمكنك تسجيل الدخول باستخدام Google'
              : 'اربط Gmail بحسابك الحالي دون إنشاء حساب جديد',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: linked
            ? const Icon(
                Icons.check_circle,
                color: Colors.green,
              )
            : linkingGoogle
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: gold,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.link,
                    color: gold,
                  ),
        onTap: linked || linkingGoogle
            ? null
            : linkGoogleAccount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.isLoggedIn;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 25),
        const Icon(
          Icons.account_circle,
          color: gold,
          size: 85,
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'حسابي',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 25),

        if (!loggedIn) ...[
          const Center(
            child: Text(
              'أهلاً بك في ShamFlix',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
              ),
              onPressed: openLogin,
              icon: const Icon(Icons.login),
              label: const Text(
                'تسجيل الدخول أو إنشاء حساب',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 15),
          accountTile(
            icon: Icons.favorite_outline,
            title: 'المفضلة',
            subtitle: 'احفظ أفلامك ومسلسلاتك المفضلة',
          ),
          accountTile(
            icon: Icons.history,
            title: 'سجل المشاهدة',
            subtitle: 'تابع ما شاهدته',
          ),
        ] else ...[
          Card(
            color: panel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_circle,
                    color: gold,
                    size: 55,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AuthService.userEmail ?? 'مستخدم ShamFlix',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF493B25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      AuthService.isAdmin ? 'مدير' : 'مستخدم',
                      style: const TextStyle(
                        color: gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          googleAccountTile(),

          if (AuthService.isAdmin)
            accountTile(
              icon: Icons.admin_panel_settings,
              title: 'إدارة ShamFlix',
              subtitle: 'إعدادات وأدوات الإدارة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminPage(),
                  ),
                );
              },
            ),

          accountTile(
            icon: Icons.favorite_outline,
            title: 'المفضلة',
            subtitle: 'قريباً: قائمة محتواك المفضل',
          ),
          accountTile(
            icon: Icons.history,
            title: 'سجل المشاهدة',
            subtitle: 'قريباً: آخر ما شاهدته',
          ),

          const SizedBox(height: 15),

          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: loading ? null : logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: gold,
                side: const BorderSide(color: gold),
              ),
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: gold,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ),
        ],
      ],
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_outline, color: gold, size: 65),
          SizedBox(height: 15),
          Text(
            'المفضلة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'سنربط المفضلة بحسابك في الخطوة القادمة',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class DetailsPage extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isSeries;
  final bool isChannel;

  const DetailsPage({
    super.key,
    required this.item,
    this.isSeries = false,
    this.isChannel = false,
  });

  Future<void> copyStreamUrl(BuildContext context) async {
    final url = valueOf(item['stream_url']);

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رابط تشغيل لهذا المحتوى'),
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رابط التشغيل')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = valueOf(
      item['title'] ?? item['name'],
      'بدون عنوان',
    );

    final poster = valueOf(
      item['poster_url'] ?? item['logo_url'],
    );

    final description = valueOf(
      item['description'],
      'لا يوجد وصف لهذا المحتوى حالياً.',
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(title),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 390,
                child: poster.isEmpty
                    ? Container(
                        color: panel,
                        child: const Icon(
                          Icons.movie,
                          color: gold,
                          size: 90,
                        ),
                      )
                    : Image.network(
                        poster,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) {
                          return Container(
                            color: panel,
                            child: const Icon(
                              Icons.movie,
                              color: gold,
                              size: 90,
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (valueOf(item['release_year']).isNotEmpty)
                          detailTag(
                            Icons.calendar_today,
                            valueOf(item['release_year']),
                          ),
                        if (valueOf(item['category']).isNotEmpty)
                          detailTag(
                            Icons.category,
                            valueOf(item['category']),
                          ),
                        if (valueOf(item['rating']).isNotEmpty)
                          detailTag(
                            Icons.star,
                            valueOf(item['rating']),
                          ),
                        detailTag(
                          isChannel
                              ? Icons.live_tv
                              : isSeries
                                  ? Icons.tv
                                  : Icons.movie,
                          isChannel
                              ? 'قناة'
                              : isSeries
                                  ? 'مسلسل'
                                  : 'فيلم',
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      'القصة والوصف',
                      style: TextStyle(
                        color: gold,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.7,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (valueOf(item['stream_url']).isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.all(15),
                          ),
                          onPressed: () => copyStreamUrl(context),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text(
                            'نسخ رابط التشغيل',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget detailTag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: gold, size: 16),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}

class ShamFlixSearch extends SearchDelegate {
  Future<List<Map<String, dynamic>>> searchContent() async {
    final movieResults = await SupabaseService.getMovies();
    final seriesResults = await SupabaseService.getSeries();

    final allResults = [
      ...movieResults,
      ...seriesResults,
    ];

    final searchText = query.trim().toLowerCase();

    if (searchText.isEmpty) return [];

    return allResults.where((item) {
      return valueOf(item['title'])
          .toLowerCase()
          .contains(searchText);
    }).toList();
  }

  @override
  String get searchFieldLabel => 'ابحث عن فيلم أو مسلسل';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
        icon: const Icon(Icons.clear),
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  Widget results(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text(
          'اكتب اسم الفيلم أو المسلسل',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: searchContent(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد نتائج',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final poster = valueOf(item['poster_url']);

            final isSeries = item['stream_url'] == null;

            return ListTile(
              leading: SizedBox(
                width: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: poster.isEmpty
                      ? const Icon(Icons.movie, color: gold)
                      : Image.network(
                          poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return const Icon(
                              Icons.movie,
                              color: gold,
                            );
                          },
                        ),
                ),
              ),
              title: Text(
                valueOf(item['title'], 'بدون عنوان'),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                isSeries ? 'مسلسل' : 'فيلم',
                style: const TextStyle(color: gold),
              ),
              onTap: () {
                close(context, null);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailsPage(
                      item: item,
                      isSeries: isSeries,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return results(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return results(context);
  }
}
