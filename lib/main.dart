
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
  MediaKit.ensureInitialized();

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
            icon: Icons.settings_outlined,
            title: 'إعدادات المشغل',
            subtitle: 'اختيار المشغل الداخلي أو VLC أو MX Player',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ShamFlixPlayerSettingsPage(),
                ),
              );
            },
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
            icon: Icons.settings_outlined,
            title: 'إعدادات المشغل',
            subtitle: 'اختيار المشغل الداخلي أو VLC أو MX Player',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ShamFlixPlayerSettingsPage(),
                ),
              );
            },
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
  bool seasonsLoading = false;
  List<Map<String, dynamic>> seasons = [];
  String? seasonsError;

  @override
  void initState() {
    super.initState();
    if (widget.isSeries) _loadSeasons();
  }

  Future<void> _loadSeasons() async {
    final id = widget.item['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() { seasonsLoading = true; seasonsError = null; });
    try {
      final rows = await SupabaseService.getSeasons(id);
      if (!mounted) return;
      setState(() => seasons = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => seasonsError = e.toString());
    } finally {
      if (mounted) setState(() => seasonsLoading = false);
    }
  }

  Future<void> copyStreamUrl(String url) async {
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رابط التشغيل')),
    );
  }

  Future<void> _chooseAndPlay({
    required String contentType,
    required String contentId,
    required String title,
    String? legacyUrl,
  }) async {
    List<Map<String, dynamic>> servers = [];
    try {
      servers = await SupabaseService.getPlaybackServers(
        contentType: contentType,
        contentId: contentId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل سيرفرات التشغيل: $e')),
      );
      return;
    }
    if (!mounted) return;

    if (servers.isEmpty) {
      final fallback = legacyUrl?.trim() ?? '';
      if (fallback.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد روابط تشغيل لهذا المحتوى')),
        );
        return;
      }
      await _startPlayback(fallback, title);
      return;
    }

    if (servers.length == 1) {
      await _startPlayback(servers.first['stream_url'].toString(), title);
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: panel,
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
                ...servers.map((server) => ListTile(
                      leading: const Icon(Icons.dns, color: gold),
                      title: Text(valueOf(server['server_name'], 'سيرفر'), style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.play_arrow, color: gold),
                      onTap: () => Navigator.pop(sheetContext, server),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _startPlayback(selected['stream_url'].toString(), title);
  }

  bool _isDirectMediaUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    return RegExp(
      r'\.(mp4|m4v|mkv|mov|webm|avi|wmv|flv|mpg|mpeg|3gp|ts|m3u8|mpd|mp3|aac|m4a|ogg|wav)$',
      caseSensitive: false,
    ).hasMatch(uri.path);
  }

  Future<void> _startPlayback(String url, String title) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط التشغيل غير صالح')),
      );
      return;
    }
    if (!_isDirectMediaUrl(url)) {
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ShamFlixWebPage(url: url, title: title),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نوع الرابط غير مدعوم داخل التطبيق')),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedPlayer = prefs.getString(_playerPreferenceKey) ?? 'internal';
    if (!mounted) return;
    if (selectedPlayer == 'internal') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ShamFlixPlayerPage(url: url, title: title),
      ));
      return;
    }
    final packages = selectedPlayer == 'vlc'
        ? <String>['org.videolan.vlc']
        : <String>['com.mxtech.videoplayer.ad', 'com.mxtech.videoplayer.pro'];
    try {
      var launched = false;
      for (final packageName in packages) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: url,
          type: 'video/*',
          package: packageName,
        );
        if (await intent.canResolveActivity() == true) {
          await intent.launch();
          launched = true;
          break;
        }
      }
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(selectedPlayer == 'vlc'
              ? 'لم يتم العثور على VLC. تأكد من تثبيته.'
              : 'لم يتم العثور على MX Player. تأكد من تثبيته.'),
          action: SnackBarAction(
            label: 'داخلي',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ShamFlixPlayerPage(url: url, title: title),
            )),
          ),
        ));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تشغيل المشغل الخارجي. جرّب المشغل الداخلي.')),
      );
    }
  }

  void _showPlayerMissing(String player) {
    final name = player == 'vlc' ? 'VLC' : 'MX Player';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تأكد من تثبيت $name على جهازك')),
    );
  }

  Widget _episodeList(Map<String, dynamic> season) {
    final seasonId = season['id']?.toString() ?? '';
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.getEpisodes(seasonId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: gold)));
        }
        if (snapshot.hasError) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('تعذر تحميل الحلقات', style: TextStyle(color: Colors.redAccent)));
        }
        final episodes = snapshot.data ?? [];
        if (episodes.isEmpty) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد حلقات منشورة في هذا الموسم', style: TextStyle(color: Colors.white54)));
        }
        return Column(
          children: episodes.map((episode) {
            final number = episode['episode_number']?.toString() ?? '';
            final episodeTitle = valueOf(episode['title'], 'الحلقة $number');
            final poster = valueOf(episode['poster_url']);
            return ListTile(
              leading: poster.isEmpty
                  ? const CircleAvatar(backgroundColor: panel, child: Icon(Icons.play_arrow, color: gold))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(poster, width: 54, height: 58, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.play_circle, color: gold)),
                    ),
              title: Text('$number - $episodeTitle', style: const TextStyle(color: Colors.white)),
              subtitle: const Text('تشغيل الحلقة', style: TextStyle(color: Colors.white54)),
              trailing: const Icon(Icons.play_circle_outline, color: gold),
              onTap: () => _chooseAndPlay(
                contentType: 'episode',
                contentId: episode['id'].toString(),
                title: episodeTitle,
                legacyUrl: episode['stream_url']?.toString(),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isSeries = widget.isSeries;
    final isChannel = widget.isChannel;
    final title = valueOf(item['title'] ?? item['name'], 'بدون عنوان');
    final poster = valueOf(item['poster_url'] ?? item['logo_url']);
    final description = valueOf(item['description'], 'لا يوجد وصف لهذا المحتوى حالياً.');

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
                    : Image.network(poster, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(color: panel, child: const Icon(Icons.movie, color: gold, size: 90))),
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
                        if (valueOf(item['release_year']).isNotEmpty) _detailTag(Icons.calendar_today, valueOf(item['release_year'])),
                        if (valueOf(item['category']).isNotEmpty) _detailTag(Icons.category, valueOf(item['category'])),
                        if (valueOf(item['rating']).isNotEmpty) _detailTag(Icons.star, valueOf(item['rating'])),
                        _detailTag(isChannel ? Icons.live_tv : isSeries ? Icons.tv : Icons.movie, isChannel ? 'قناة' : isSeries ? 'مسلسل' : 'فيلم'),
                      ],
                    ),
                    const SizedBox(height: 25),
                    const Text('القصة والوصف', style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(description, style: const TextStyle(color: Colors.white70, height: 1.7, fontSize: 15)),
                    const SizedBox(height: 25),
                    if (!isSeries)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, padding: const EdgeInsets.all(15)),
                          onPressed: () => _chooseAndPlay(
                            contentType: isChannel ? 'channel' : 'movie',
                            contentId: item['id'].toString(),
                            title: title,
                            legacyUrl: item['stream_url']?.toString(),
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('تشغيل الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    if (valueOf(item['stream_url']).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          onPressed: () => copyStreamUrl(valueOf(item['stream_url'])),
                          icon: const Icon(Icons.copy, color: gold),
                          label: const Text('نسخ رابط التشغيل', style: TextStyle(color: gold)),
                        ),
                      ),
                    ],
                    if (isSeries) ...[
                      const SizedBox(height: 22),
                      const Text('المواسم والحلقات', style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (seasonsLoading)
                        const Center(child: CircularProgressIndicator(color: gold))
                      else if (seasonsError != null)
                        Text('تعذر تحميل المواسم: $seasonsError', style: const TextStyle(color: Colors.redAccent))
                      else if (seasons.isEmpty)
                        const Text('لا توجد مواسم منشورة حالياً', style: TextStyle(color: Colors.white54))
                      else
                        ...seasons.map((season) => Card(
                              color: panel,
                              child: ExpansionTile(
                                iconColor: gold,
                                collapsedIconColor: gold,
                                title: Text(valueOf(season['name'], 'الموسم ${season['season_number']}'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                children: [_episodeList(season)],
                              ),
                            )),
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

const String _playerPreferenceKey = 'shamflix_player_preference';

class ShamFlixPlayerSettingsPage extends StatefulWidget {
  const ShamFlixPlayerSettingsPage({super.key});

  @override
  State<ShamFlixPlayerSettingsPage> createState() => _ShamFlixPlayerSettingsPageState();
}

class _ShamFlixPlayerSettingsPageState extends State<ShamFlixPlayerSettingsPage> {
  String selectedPlayer = 'internal';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      selectedPlayer = prefs.getString(_playerPreferenceKey) ?? 'internal';
      loading = false;
    });
  }

  Future<void> _save(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerPreferenceKey, value);
    if (!mounted) return;
    setState(() => selectedPlayer = value);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ اختيار المشغل')));
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
                  const Text('اختر المشغل الافتراضي لجميع الأفلام والحلقات والقنوات', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 14),
                  _playerOption('internal', 'المشغل الداخلي', 'تشغيل داخل تطبيق ShamFlix', Icons.smart_display),
                  _playerOption('vlc', 'VLC', 'يتطلب تثبيت تطبيق VLC', Icons.play_circle),
                  _playerOption('mx', 'MX Player', 'يتطلب تثبيت تطبيق MX Player', Icons.ondemand_video),
                ],
              ),
      ),
    );
  }

  Widget _playerOption(String value, String title, String subtitle, IconData icon) {
    return Card(
      color: panel,
      child: RadioListTile<String>(
        value: value,
        groupValue: selectedPlayer,
        activeColor: gold,
        secondary: Icon(icon, color: gold),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        onChanged: (next) { if (next != null) _save(next); },
      ),
    );
  }
}

class ShamFlixPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  const ShamFlixPlayerPage({super.key, required this.url, required this.title});
  @override
  State<ShamFlixPlayerPage> createState() => _ShamFlixPlayerPageState();
}
class _ShamFlixPlayerPageState extends State<ShamFlixPlayerPage> {
  late final Player player;
  late final VideoController controller;
  String? error;
  bool opening = true;
  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    player.stream.error.listen((message) {
      if (!mounted) return;
      setState(() { error = message; opening = false; });
    });
    _open();
  }
  Future<void> _open() async {
    try {
      await player.open(Media(widget.url));
      if (mounted) setState(() => opening = false);
    } catch (e) {
      if (mounted) setState(() {
        opening = false;
        error = 'تعذر تشغيل هذا الرابط: ' + e.toString();
      });
    }
  }
  String _time(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = value.inHours;
    final m = value.inMinutes.remainder(60);
    final s = value.inSeconds.remainder(60);
    if (h > 0) return two(h) + ':' + two(m) + ':' + two(s);
    return two(m) + ':' + two(s);
  }
  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: bg, title: Text(widget.title)),
        body: error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: Center(
                    child: opening
                        ? const CircularProgressIndicator(color: gold)
                        : Video(controller: controller, fit: BoxFit.contain,
                            controls: NoVideoControls),
                  )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: StreamBuilder<Duration>(
                      stream: player.stream.position,
                      builder: (context, ps) {
                        final position = ps.data ?? Duration.zero;
                        return StreamBuilder<Duration>(
                          stream: player.stream.duration,
                          builder: (context, ds) {
                            final duration = ds.data ?? Duration.zero;
                            final max = duration.inMilliseconds > 0
                                ? duration.inMilliseconds.toDouble() : 1.0;
                            final value = position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
                            return Column(children: [
                              Slider(
                                value: value, max: max, activeColor: gold,
                                inactiveColor: Colors.white24,
                                onChanged: duration == Duration.zero ? null :
                                    (next) => player.seek(Duration(milliseconds: next.round())),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_time(position), style: const TextStyle(color: Colors.white70)),
                                  Text(_time(duration), style: const TextStyle(color: Colors.white70)),
                                ],
                              ),
                            ]);
                          },
                        );
                      },
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(iconSize: 48, color: gold,
                          onPressed: () => player.seek(player.state.position > const Duration(seconds: 10)
                                  ? player.state.position - const Duration(seconds: 10)
                                  : Duration.zero),
                          icon: const Icon(Icons.replay_10)),
                        IconButton(iconSize: 62, color: gold,
                          onPressed: () => player.playOrPause(),
                          icon: Icon(playing ? Icons.pause_circle : Icons.play_circle)),
                        IconButton(iconSize: 48, color: gold,
                          onPressed: () => player.seek(player.state.position + const Duration(seconds: 10)),
                          icon: const Icon(Icons.forward_10)),
                      ]);
                    },
                  ),
                  const SizedBox(height: 18),
                ],
              ),
      ),
    );
  }
}

class ShamFlixWebPage extends StatefulWidget {
  final String url;
  final String title;
  const ShamFlixWebPage({super.key, required this.url, required this.title});
  @override
  State<ShamFlixWebPage> createState() => _ShamFlixWebPageState();
}
class _ShamFlixWebPageState extends State<ShamFlixWebPage> {
  late final WebViewController controller;
  int progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  String? pageError;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => pageError = null);
        },
        onPageFinished: (_) async {
          final back = await controller.canGoBack();
          final forward = await controller.canGoForward();
          if (mounted) setState(() {
            canGoBack = back;
            canGoForward = forward;
            progress = 100;
          });
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => pageError =
                'تعذر تحميل الصفحة. تحقق من اتصال الإنترنت أو جرّب سيرفراً آخر.');
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'رجوع', onPressed: canGoBack ? () => controller.goBack() : null,
                icon: const Icon(Icons.arrow_back)),
            IconButton(tooltip: 'تقدم', onPressed: canGoForward ? () => controller.goForward() : null,
                icon: const Icon(Icons.arrow_forward)),
            IconButton(tooltip: 'تحديث', onPressed: () => controller.reload(),
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Column(children: [
          if (progress < 100)
            LinearProgressIndicator(value: progress / 100, color: gold, backgroundColor: panel),
          Expanded(
            child: pageError != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(pageError!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ))
                : WebViewWidget(controller: controller),
          ),
        ]),
      ),
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

// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تم ربط المواسم والحلقات والسيرفرات بواجهة المشاهدة.
// تم إصلاح إنشاء VideoProgressColors ليتوافق مع إصدار الحزمة.
// أضيفت إعدادات المشغل للمستخدمين المسجلين وغير المسجلين، والمشغل الداخلي والخارجي.
// ==========================================

// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تم اعتماد media_kit/libmpv لتوسيع دعم صيغ الفيديو والبث المباشر.
// تمت إضافة متصفح WebView مدمج لروابط صفحات مواقع المشاهدة.
// تم فصل روابط صفحات المواقع عن روابط ملفات الفيديو المباشرة.
// ==========================================