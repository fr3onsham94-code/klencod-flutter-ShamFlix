
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'admin_auth_service.dart';
import 'supabase_service.dart';

const Color adminBg = Color(0xFF090909);
const Color adminGold = Color(0xFFD6AC55);
const Color adminPanel = Color(0xFF191919);

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> movies = [];
  List<Map<String, dynamic>> users = [];

  bool loading = true;
  bool usersLoading = false;
  bool showUsers = false;

  String? errorMessage;
  String? usersError;

  Map<String, String> get headers => {
        'apikey': SupabaseService.publishableKey,
        'Authorization': 'Bearer ${AuthService.accessToken ?? ''}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Uri get moviesUrl => Uri.parse(
        '${SupabaseService.projectUrl}/rest/v1/movies',
      );

  Uri get usersFunctionUrl => Uri.parse(
        '${SupabaseService.projectUrl}/functions/v1/admin-users',
      );

  @override
  void initState() {
    super.initState();
    loadMovies();
  }

  // =========================
  // الأفلام
  // =========================

  Future<void> loadMovies() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage = 'ليس لديك صلاحية الوصول إلى لوحة الإدارة';
      });
      return;
    }

    if (mounted) {
      setState(() {
        loading = true;
        errorMessage = null;
      });
    }

    try {
      final response = await http.get(
        moviesUrl.replace(
          queryParameters: {
            'select': '*',
            'order': 'created_at.desc',
          },
        ),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception(_readError(response));
      }

      final data = jsonDecode(response.body) as List;

      movies = data
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      errorMessage = e.toString();
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> saveMovie(
    Map<String, dynamic> movie, {
    String? id,
  }) async {
    final isEditing = id != null;

    final uri = isEditing
        ? moviesUrl.replace(
            queryParameters: {'id': 'eq.$id'},
          )
        : moviesUrl;

    final response = isEditing
        ? await http.patch(
            uri,
            headers: headers,
            body: jsonEncode(movie),
          )
        : await http.post(
            uri,
            headers: headers,
            body: jsonEncode(movie),
          );

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception(_readError(response));
    }

    await loadMovies();
  }

  Future<void> deleteMovie(String id) async {
    final response = await http.delete(
      moviesUrl.replace(
        queryParameters: {'id': 'eq.$id'},
      ),
      headers: headers,
    );

    if (response.statusCode != 200 &&
        response.statusCode != 204) {
      throw Exception(_readError(response));
    }

    await loadMovies();
  }

  Future<void> togglePublish(
    Map<String, dynamic> movie,
  ) async {
    final id = movie['id']?.toString();

    if (id == null || id.isEmpty) return;

    final published = movie['is_published'] == true;

    try {
      final response = await http.patch(
        moviesUrl.replace(
          queryParameters: {'id': 'eq.$id'},
        ),
        headers: headers,
        body: jsonEncode({
          'is_published': !published,
        }),
      );

      if (response.statusCode != 200 &&
          response.statusCode != 204) {
        throw Exception(_readError(response));
      }

      await loadMovies();

      showMessage(
        published ? 'تم إلغاء نشر الفيلم' : 'تم نشر الفيلم',
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  // =========================
  // إدارة المستخدمين
  // =========================

  Future<Map<String, dynamic>> callUsersFunction(
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      usersFunctionUrl,
      headers: {
        'apikey': SupabaseService.publishableKey,
        'Authorization':
            'Bearer ${AuthService.accessToken ?? ''}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode != 200) {
      String message = 'حدث خطأ أثناء تنفيذ العملية';

      if (decoded is Map) {
        message = decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            message;
      }

      throw Exception(message);
    }

    if (decoded is! Map) {
      throw Exception('استجابة غير صحيحة من الخادم');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<void> loadUsers() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return;
    }

    setState(() {
      usersLoading = true;
      usersError = null;
    });

    try {
      final result = await callUsersFunction({
        'action': 'list',
        'page': 1,
      });

      final data = result['users'] as List? ?? [];

      users = data
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      usersError = e.toString();
    }

    if (mounted) {
      setState(() => usersLoading = false);
    }
  }

  bool isUserBanned(Map<String, dynamic> user) {
    final value = user['banned_until'];

    if (value == null) return false;

    final date = DateTime.tryParse(value.toString());

    if (date == null) return false;

    return date.isAfter(DateTime.now().toUtc());
  }

  Future<void> changeUserStatus(
    Map<String, dynamic> user, {
    required bool ban,
  }) async {
    final id = user['id']?.toString();

    if (id == null || id.isEmpty) return;

    final email = user['email']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: adminPanel,
          title: Text(
            ban ? 'حظر المستخدم' : 'فك حظر المستخدم',
            style: const TextStyle(color: adminGold),
          ),
          content: Text(
            ban
                ? 'هل تريد حظر الحساب التالي؟\n$email'
                : 'هل تريد فك الحظر عن الحساب التالي؟\n$email',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ban ? Colors.red : Colors.green,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(ban ? 'حظر' : 'فك الحظر'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await callUsersFunction({
        'action': ban ? 'ban' : 'unban',
        'user_id': id,
      });

      showMessage(
        ban ? 'تم حظر المستخدم' : 'تم فك حظر المستخدم',
      );

      await loadUsers();
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  Future<void> changeAdminRole(
    Map<String, dynamic> user, {
    required bool makeAdmin,
  }) async {
    final id = user['id']?.toString();

    if (id == null || id.isEmpty) return;

    final email = user['email']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: adminPanel,
          title: Text(
            makeAdmin ? 'ترقية إلى مدير' : 'إزالة صلاحية المدير',
            style: const TextStyle(color: adminGold),
          ),
          content: Text(
            makeAdmin
                ? 'هل تريد منح هذا الحساب صلاحية المدير؟\n$email'
                : 'هل تريد إزالة صلاحية المدير من هذا الحساب؟\n$email',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: adminGold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await callUsersFunction({
        'action': 'set_admin',
        'user_id': id,
        'is_admin': makeAdmin,
      });

      showMessage(
        makeAdmin
            ? 'تمت ترقية المستخدم إلى مدير'
            : 'تمت إزالة صلاحية المدير',
      );

      await loadUsers();
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  Widget userCard(Map<String, dynamic> user) {
    final email = user['email']?.toString() ?? 'بريد غير معروف';
    final isAdmin = user['role'] == 'admin';
    final banned = isUserBanned(user);

    final createdAt = user['created_at']?.toString() ?? '';

    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: adminGold.withOpacity(0.15),
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings : Icons.person,
                    color: adminGold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip(
                  isAdmin ? 'مدير' : 'مستخدم',
                  isAdmin ? adminGold : Colors.blueGrey,
                ),
                _statusChip(
                  banned ? 'محظور' : 'نشط',
                  banned ? Colors.red : Colors.green,
                ),
              ],
            ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                'تاريخ التسجيل: ${createdAt.split('T').first}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
            const Divider(color: Colors.white12, height: 22),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                TextButton.icon(
                  onPressed: () => changeUserStatus(
                    user,
                    ban: !banned,
                  ),
                  icon: Icon(
                    banned ? Icons.lock_open : Icons.block,
                    color: banned ? Colors.green : Colors.redAccent,
                    size: 19,
                  ),
                  label: Text(
                    banned ? 'فك الحظر' : 'حظر',
                    style: TextStyle(
                      color: banned ? Colors.green : Colors.redAccent,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => changeAdminRole(
                    user,
                    makeAdmin: !isAdmin,
                  ),
                  icon: Icon(
                    isAdmin
                        ? Icons.remove_moderator
                        : Icons.admin_panel_settings,
                    color: adminGold,
                    size: 19,
                  ),
                  label: Text(
                    isAdmin ? 'إزالة المدير' : 'ترقية لمدير',
                    style: const TextStyle(color: adminGold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget usersSection() {
    if (usersLoading) {
      return const Center(
        child: CircularProgressIndicator(color: adminGold),
      );
    }

    if (usersError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 45,
              ),
              const SizedBox(height: 12),
              Text(
                usersError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 15),
              FilledButton(
                onPressed: loadUsers,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (users.isEmpty) {
      return RefreshIndicator(
        color: adminGold,
        onRefresh: loadUsers,
        child: ListView(
          children: const [
            SizedBox(height: 130),
            Center(
              child: Text(
                'لا يوجد مستخدمون لعرضهم',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: adminGold,
      onRefresh: loadUsers,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 25),
        itemCount: users.length,
        itemBuilder: (context, index) {
          return userCard(users[index]);
        },
      ),
    );
  }

  // =========================
  // أدوات عامة
  // =========================

  String _readError(http.Response response) {
    try {
      final data = jsonDecode(response.body);

      if (data is Map) {
        return data['message']?.toString() ??
            data['msg']?.toString() ??
            data['details']?.toString() ??
            'حدث خطأ في قاعدة البيانات';
      }
    } catch (_) {}

    return 'خطأ في الاتصال: ${response.statusCode}';
  }

  int? _extractTmdbId(String value) {
    final input = value.trim();

    final match = RegExp(
      r'/(?:movie|tv)/(\d+)',
    ).firstMatch(input);

    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    return int.tryParse(input);
  }

  void showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // =========================
  // نموذج الفيلم
  // =========================

  Future<void> openMovieForm({
    Map<String, dynamic>? existing,
  }) async {
    final titleController = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );

    final tmdbController = TextEditingController(
      text: existing?['tmdb_id']?.toString() ?? '',
    );

    final posterController = TextEditingController(
      text: existing?['poster_url']?.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );

    final categoryController = TextEditingController(
      text: existing?['category']?.toString() ?? '',
    );

    final yearController = TextEditingController(
      text: existing?['release_year']?.toString() ?? '',
    );

    final ratingController = TextEditingController(
      text: existing?['rating']?.toString() ?? '',
    );

    final streamController = TextEditingController(
      text: existing?['stream_url']?.toString() ?? '',
    );

    bool published = existing?['is_published'] == true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: adminPanel,
                title: Text(
                  existing == null ? 'إضافة فيلم جديد' : 'تعديل الفيلم',
                  style: const TextStyle(color: adminGold),
                ),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        adminField(
                          titleController,
                          'اسم الفيلم',
                          required: true,
                        ),
                        adminField(
                          tmdbController,
                          'رابط TMDB أو رقم الفيلم',
                        ),
                        adminField(
                          posterController,
                          'رابط صورة الفيلم',
                        ),
                        adminField(
                          descriptionController,
                          'وصف الفيلم',
                          maxLines: 4,
                        ),
                        adminField(
                          categoryController,
                          'التصنيف',
                        ),
                        adminField(
                          yearController,
                          'سنة الإصدار',
                          keyboard: TextInputType.number,
                        ),
                        adminField(
                          ratingController,
                          'التقييم',
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        adminField(
                          streamController,
                          'رابط التشغيل',
                        ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: published,
                          activeColor: adminGold,
                          checkColor: Colors.black,
                          title: const Text(
                            'نشر الفيلم للمستخدمين',
                            style: TextStyle(color: Colors.white),
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              published = value ?? false;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: adminGold,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      final title = titleController.text.trim();

                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال اسم الفيلم'),
                          ),
                        );
                        return;
                      }

                      final tmdbId = _extractTmdbId(
                        tmdbController.text,
                      );

                      Navigator.pop(dialogContext, {
                        'title': title,
                        'tmdb_id': tmdbId,
                        'poster_url': posterController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'category': categoryController.text.trim(),
                        'release_year':
                            int.tryParse(yearController.text.trim()),
                        'rating':
                            double.tryParse(ratingController.text.trim()),
                        'stream_url': streamController.text.trim(),
                        'is_published': published,
                      });
                    },
                    child: const Text('حفظ الفيلم'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    tmdbController.dispose();
    posterController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
    yearController.dispose();
    ratingController.dispose();
    streamController.dispose();

    if (result == null) return;

    try {
      final rawId = existing?['id'];
      final String? id = rawId?.toString();

      await saveMovie(result, id: id);

      showMessage(
        existing == null
            ? 'تمت إضافة الفيلم بنجاح'
            : 'تم تعديل الفيلم بنجاح',
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  Widget adminField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: TextDirection.rtl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: const TextStyle(color: Colors.white60),
          filled: true,
          fillColor: adminBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: adminGold),
          ),
        ),
      ),
    );
  }

  Future<void> confirmDelete(
    Map<String, dynamic> movie,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: adminPanel,
          title: const Text(
            'حذف الفيلم',
            style: TextStyle(color: adminGold),
          ),
          content: Text(
            'هل تريد حذف فيلم "${movie['title']}" نهائياً؟',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'حذف',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final rawId = movie['id'];
    final id = rawId?.toString();

    if (id == null || id.isEmpty) return;

    try {
      await deleteMovie(id);
      showMessage('تم حذف الفيلم');
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  Widget movieCard(Map<String, dynamic> movie) {
    final published = movie['is_published'] == true;
    final poster = movie['poster_url']?.toString() ?? '';

    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 75,
                height: 105,
                child: poster.isEmpty
                    ? const ColoredBox(
                        color: adminBg,
                        child: Icon(
                          Icons.movie,
                          color: adminGold,
                          size: 35,
                        ),
                      )
                    : Image.network(
                        poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return const ColoredBox(
                            color: adminBg,
                            child: Icon(
                              Icons.movie,
                              color: adminGold,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie['title']?.toString() ?? 'بدون عنوان',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    movie['release_year']?.toString() ?? 'سنة غير محددة',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    published ? 'منشور' : 'مسودة',
                    style: TextStyle(
                      color: published ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'تعديل',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          openMovieForm(existing: movie);
                        },
                        icon: const Icon(
                          Icons.edit,
                          color: adminGold,
                        ),
                      ),
                      IconButton(
                        tooltip: published ? 'إلغاء النشر' : 'نشر',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => togglePublish(movie),
                        icon: Icon(
                          published
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => confirmDelete(movie),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // واجهة لوحة الإدارة
  // =========================

  Widget sectionHeader() {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: adminPanel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _sectionButton(
              title: 'الأفلام',
              icon: Icons.movie_creation_outlined,
              selected: !showUsers,
              onTap: () {
                setState(() => showUsers = false);
                loadMovies();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _sectionButton(
              title: 'المستخدمون',
              icon: Icons.people_outline,
              selected: showUsers,
              onTap: () {
                setState(() => showUsers = true);
                loadUsers();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionButton({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? adminGold : adminBg,
        foregroundColor: selected ? Colors.black : Colors.white70,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 6),
          Text(title),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return Scaffold(
        backgroundColor: adminBg,
        appBar: AppBar(
          backgroundColor: adminBg,
          title: const Text('إدارة ShamFlix'),
        ),
        body: const Center(
          child: Text(
            'هذه الصفحة مخصصة للمديرين فقط',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: adminBg,
        appBar: AppBar(
          backgroundColor: adminBg,
          title: const Text(
            'لوحة إدارة ShamFlix',
            style: TextStyle(
              color: adminGold,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              onPressed: showUsers ? loadUsers : loadMovies,
              icon: const Icon(Icons.refresh, color: adminGold),
            ),
          ],
        ),
        floatingActionButton: showUsers
            ? null
            : FloatingActionButton.extended(
                backgroundColor: adminGold,
                foregroundColor: Colors.black,
                onPressed: () => openMovieForm(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة فيلم'),
              ),
        body: Column(
          children: [
            sectionHeader(),

            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: adminPanel,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    showUsers
                        ? Icons.people_outline
                        : Icons.movie_creation_outlined,
                    color: adminGold,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      showUsers ? 'إدارة المستخدمين' : 'إدارة الأفلام',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Text(
                    showUsers
                        ? '${users.length} مستخدم'
                        : '${movies.length} فيلم',
                    style: const TextStyle(
                      color: adminGold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: showUsers
                  ? usersSection()
                  : loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: adminGold,
                          ),
                        )
                      : errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 45,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 15),
                                    FilledButton(
                                      onPressed: loadMovies,
                                      child: const Text('إعادة المحاولة'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : movies.isEmpty
                              ? const Center(
                                  child: Text(
                                    'لا توجد أفلام حالياً\nاضغط إضافة فيلم للبدء',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      height: 1.8,
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  color: adminGold,
                                  onRefresh: loadMovies,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.only(
                                      bottom: 90,
                                    ),
                                    itemCount: movies.length,
                                    itemBuilder: (context, index) {
                                      return movieCard(movies[index]);
                                    },
                                  ),
                                ),
            ),
          ],
        ),
      ),
    );
  }
}
