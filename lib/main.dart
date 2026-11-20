
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:android_intent_plus/android_intent.dart';

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
        showCategoryBadge = value == true ||
            value.toString().toLowerCase() == 'true';
      });
    } catch (_) {
      // في حال فشل الاتصال يبقى الإعداد السابق كما هو.
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
      loadCategoryBadgeSetting(),
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

                    // إظهار التصنيف فوق البوستر حسب إعداد الإدارة
                    if (showCategoryBadge &&
                        category.trim().isNotEmpty)
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

        accountTile(
            icon: Icons.settings_outlined,
            title: 'إعدادات المشغل',
            subtitle: 'اختيار مشغل الفيديو الافتراضي',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayerSettingsPage()),
              );
            },
          ),

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

class PlayerPreference {
  static const String key = 'shamflix_default_player';
  static const String internal = 'internal';
  static const String vlc = 'vlc';
  static const String mx = 'mx';

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? internal;
  }

  static Future<void> set(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static String label(String value) {
    if (value == vlc) return 'VLC Player';
    if (value == mx) return 'MX Player';
    return 'المشغل الداخلي';
  }
}

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  String selected = PlayerPreference.internal;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await PlayerPreference.get();
    if (!mounted) return;
    setState(() {
      selected = value;
      loading = false;
    });
  }

  Future<void> _save(String value) async {
    await PlayerPreference.set(value);
    if (!mounted) return;
    setState(() => selected = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ المشغل الافتراضي: ' + PlayerPreference.label(value))),
    );
  }

  Widget _option(String value, String title, String subtitle, IconData icon) {
    return Card(
      color: panel,
      child: RadioListTile<String>(
        value: value,
        groupValue: selected,
        activeColor: gold,
        secondary: Icon(icon, color: gold),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        onChanged: (v) {
          if (v != null) _save(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: const Text('إعدادات المشغل')),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: gold))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'اختر مشغل الفيديو الذي تريد استخدامه دائماً. يمكنك تغييره لاحقاً من هنا.',
                    style: TextStyle(color: Colors.white70, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  _option(PlayerPreference.internal, 'المشغل الداخلي', 'تشغيل الفيديو داخل تطبيق ShamFlix', Icons.smart_display),
                  _option(PlayerPreference.vlc, 'VLC Player', 'فتح الفيديو باستخدام تطبيق VLC المثبت على جهازك', Icons.play_circle_outline),
                  _option(PlayerPreference.mx, 'MX Player', 'فتح الفيديو باستخدام تطبيق MX Player المثبت على جهازك', Icons.ondemand_video),
                  const SizedBox(height: 12),
                  const Text(
                    'ملاحظة: يجب تثبيت VLC أو MX Player على الجهاز لاستخدامهما.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }
}

class PlaybackPage extends StatefulWidget {
  final String url;
  final String title;

  const PlaybackPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  VideoPlayerController? controller;
  String selectedPlayer = PlayerPreference.internal;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    selectedPlayer = await PlayerPreference.get();
    if (!mounted) return;

    if (selectedPlayer != PlayerPreference.internal) {
      await _openExternal();
      return;
    }

    try {
      final video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      controller = video;
      await video.initialize();
      await video.setLooping(false);
      await video.play();
      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر تشغيل الفيديو داخل التطبيق. جرّب مشغلاً خارجياً.';
      });
    }
  }

  Future<void> _openExternal() async {
    final packageName = selectedPlayer == PlayerPreference.vlc
        ? 'org.videolan.vlc'
        : 'com.mxtech.videoplayer.ad';

    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: widget.url,
        type: 'video/*',
        package: packageName,
      );
      await intent.launch();
      if (!mounted) return;
      setState(() => loading = false);
    } catch (_) {
      if (selectedPlayer == PlayerPreference.mx) {
        try {
          final proIntent = AndroidIntent(
            action: 'action_view',
            data: widget.url,
            type: 'video/*',
            package: 'com.mxtech.videoplayer.pro',
          );
          await proIntent.launch();
          if (!mounted) return;
          setState(() => loading = false);
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'لم يتم العثور على ' + PlayerPreference.label(selectedPlayer) +
            ' أو تعذر فتح الرابط. ثبّت التطبيق أو غيّر المشغل من الإعدادات.';
      });
    }
  }

  Future<void> _useInternal() async {
    await PlayerPreference.set(PlayerPreference.internal);
    if (!mounted) return;
    setState(() {
      selectedPlayer = PlayerPreference.internal;
      loading = true;
      error = null;
    });
    await controller?.dispose();
    controller = null;
    await _initialize();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(widget.title),
        ),
        body: Center(
          child: loading
              ? const CircularProgressIndicator(color: gold)
              : error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.orange, size: 48),
                          const SizedBox(height: 14),
                          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: _useInternal,
                            icon: const Icon(Icons.smart_display),
                            label: const Text('جرّب المشغل الداخلي'),
                          ),
                        ],
                      ),
                    )
                  : selectedPlayer != PlayerPreference.internal
                      ? const Text(
                          'تم إرسال الفيديو إلى المشغل الخارجي. إذا لم يفتح، تأكد من تثبيته.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        )
                      : video == null || !video.value.isInitialized
                          ? const Text('تعذر تجهيز الفيديو', style: TextStyle(color: Colors.white70))
                          : GestureDetector(
                              onTap: () {
                                setState(() {
                                  video.value.isPlaying ? video.pause() : video.play();
                                });
                              },
                              child: AspectRatio(
                                aspectRatio: video.value.aspectRatio,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(video),
                                    if (!video.value.isPlaying)
                                      const Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
                                    Positioned(
                                      bottom: 8,
                                      left: 12,
                                      right: 12,
                                      child: VideoProgressIndicator(
                                        video,
                                        allowScrubbing: true,
                                        colors: const VideoProgressColors(
                                          playedColor: gold,
                                          bufferedColor: Colors.white38,
                                          backgroundColor: Colors.white12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
        ),
      ),
    );
  }
}

class DetailsPage extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isSeries;
  final bool isChannel;

  const DetailsPage({
    super.key,
    required this.item,
    this.isSeries = false,
    this.isChannel = false,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late Future<List<Map<String, dynamic>>> seasonsFuture;
  late Future<List<Map<String, dynamic>>> serversFuture;

  @override
  void initState() {
    super.initState();
    seasonsFuture = _loadSeasons();
    serversFuture = _loadMainServers();
  }

  Future<List<Map<String, dynamic>>> _loadSeasons() {
    if (!widget.isSeries) return Future.value([]);
    return SupabaseService.getSeasons(valueOf(widget.item['id']));
  }

  Future<List<Map<String, dynamic>>> _loadMainServers() {
    final id = valueOf(widget.item['id']);
    if (widget.isChannel) {
      return SupabaseService.getPlaybackServers(channelId: id);
    }
    if (!widget.isSeries) {
      return SupabaseService.getPlaybackServers(movieId: id);
    }
    return Future.value([]);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPlayback({
    required String url,
    required String title,
    required String type,
    required String contentId,
  }) async {
    List<Map<String, dynamic>> servers;
    try {
      servers = await SupabaseService.getPlaybackServers(
        movieId: type == 'movie' ? contentId : null,
        episodeId: type == 'episode' ? contentId : null,
        channelId: type == 'channel' ? contentId : null,
      );
    } catch (e) {
      if (!mounted) return;
      _message('تعذر تحميل سيرفرات التشغيل: ' + e.toString());
      return;
    }

    if (!mounted) return;
    final legacyUrl = type == 'episode'
        ? url
        : valueOf(widget.item['stream_url']);
    final choices = <Map<String, dynamic>>[
      ...servers,
      if (legacyUrl.isNotEmpty)
        {
          'server_name': 'الرابط الأساسي',
          'stream_url': legacyUrl,
        },
    ];

    if (choices.isEmpty && url.isNotEmpty) {
      choices.add({'server_name': 'الرابط الأساسي', 'stream_url': url});
    }

    if (choices.isEmpty) {
      _message('لا توجد روابط تشغيل متاحة لهذا المحتوى');
      return;
    }

    if (choices.length == 1) {
      _launchPlayer(
        choices.first['stream_url'].toString(),
        title,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('اختر سيرفر التشغيل', style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...choices.map((server) => Card(
                      color: bg,
                      child: ListTile(
                        leading: const Icon(Icons.dns_outlined, color: gold),
                        title: Text(valueOf(server['server_name'], 'سيرفر'), style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          valueOf(server['stream_url']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        trailing: const Icon(Icons.play_circle_outline, color: gold),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _launchPlayer(server['stream_url'].toString(), title);
                        },
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _launchPlayer(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaybackPage(url: url, title: title),
      ),
    );
  }

  Widget _buildEpisodes(String seasonId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.getEpisodes(seasonId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: gold)),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('تعذر تحميل الحلقات', style: TextStyle(color: Colors.redAccent)),
          );
        }
        final episodes = snapshot.data ?? [];
        if (episodes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('لا توجد حلقات منشورة في هذا الموسم', style: TextStyle(color: Colors.white54)),
          );
        }
        return Column(
          children: episodes.map((episode) {
            final epTitle = valueOf(episode['title'], 'الحلقة');
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.play_circle_outline, color: gold, size: 30),
              title: Text(
                'الحلقة ' + valueOf(episode['episode_number']) + ' - ' + epTitle,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                valueOf(episode['description'], 'اضغط للتشغيل'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () async {
                await _openPlayback(
                  url: valueOf(episode['stream_url']),
                  title: epTitle,
                  type: 'episode',
                  contentId: valueOf(episode['id']),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _seriesSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: seasonsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: gold));
        }
        if (snapshot.hasError) {
          return const Text('تعذر تحميل المواسم', style: TextStyle(color: Colors.redAccent));
        }
        final seasons = snapshot.data ?? [];
        if (seasons.isEmpty) {
          return const Text('لا توجد مواسم منشورة حالياً', style: TextStyle(color: Colors.white54));
        }
        return Column(
          children: seasons.map((season) {
            final seasonName = valueOf(
              season['name'],
              'الموسم ' + valueOf(season['season_number']),
            );
            return Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.white10),
              child: ExpansionTile(
                iconColor: gold,
                collapsedIconColor: gold,
                title: Text(seasonName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                children: [_buildEpisodes(valueOf(season['id']))],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _copyUrl() async {
    final url = valueOf(widget.item['stream_url']);
    if (url.isEmpty) {
      _message('لا يوجد رابط أساسي لنسخه');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _message('تم نسخ رابط التشغيل');
  }

  @override
  Widget build(BuildContext context) {
    final title = valueOf(widget.item['title'] ?? widget.item['name'], 'بدون عنوان');
    final poster = valueOf(widget.item['poster_url'] ?? widget.item['logo_url']);
    final description = valueOf(widget.item['description'], 'لا يوجد وصف لهذا المحتوى حالياً.');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: Text(title)),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 390,
                child: poster.isEmpty
                    ? Container(color: panel, child: const Icon(Icons.movie, color: gold, size: 90))
                    : Image.network(
                        poster,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          color: panel,
                          child: const Icon(Icons.movie, color: gold, size: 90),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (valueOf(widget.item['release_year']).isNotEmpty)
                          _detailTag(Icons.calendar_today, valueOf(widget.item['release_year'])),
                        if (valueOf(widget.item['category']).isNotEmpty)
                          _detailTag(Icons.category, valueOf(widget.item['category'])),
                        if (valueOf(widget.item['rating']).isNotEmpty)
                          _detailTag(Icons.star, valueOf(widget.item['rating'])),
                        _detailTag(
                          widget.isChannel ? Icons.live_tv : widget.isSeries ? Icons.tv : Icons.movie,
                          widget.isChannel ? 'قناة' : widget.isSeries ? 'مسلسل' : 'فيلم',
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    const Text('القصة والوصف', style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(description, style: const TextStyle(color: Colors.white70, height: 1.7, fontSize: 15)),
                    const SizedBox(height: 25),
                    if (widget.isSeries) ...[
                      const Text('المواسم والحلقات', style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      _seriesSection(),
                    ] else ...[
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: serversFuture,
                        builder: (context, snapshot) {
                          final count = snapshot.data?.length ?? 0;
                          return SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.all(15),
                              ),
                              onPressed: snapshot.connectionState == ConnectionState.waiting
                                  ? null
                                  : () => _openPlayback(
                                        url: valueOf(widget.item['stream_url']),
                                        title: title,
                                        type: widget.isChannel ? 'channel' : 'movie',
                                        contentId: valueOf(widget.item['id']),
                                      ),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(count > 1 ? 'تشغيل واختيار السيرفر (' + count.toString() + ')' : 'تشغيل الآن'),
                            ),
                          );
                        },
                      ),
                      if (valueOf(widget.item['stream_url']).isNotEmpty)
                        Align(
                          alignment: Alignment.center,
                          child: TextButton.icon(
                            onPressed: _copyUrl,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('نسخ الرابط الأساسي'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailTag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: gold, size: 16),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white70)),
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
