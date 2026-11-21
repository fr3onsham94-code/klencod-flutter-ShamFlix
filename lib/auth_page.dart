
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_auth_service.dart';

const Color bg = Color(0xFF090909);
const Color gold = Color(0xFFE50914);
const Color panel = Color(0xFF191919);

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  StreamSubscription<AuthState>? _authSubscription;
  bool _googleSignInPending = false;

  bool isLogin = true;
  bool isLoading = false;
  bool hidePassword = true;
  bool isPasswordRecovery = false;

  @override
  void initState() {
    super.initState();

    _authSubscription =
        AuthService.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && _googleSignInPending) {
        _googleSignInPending = false;
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (!mounted) return;

        setState(() {
          isPasswordRecovery = true;
          isLogin = true;
        });

        showMessage('أدخل كلمة المرور الجديدة لحسابك');
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool validateEmail(String email) {
    return email.contains('@') && email.contains('.');
  }

  Future<void> submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!isPasswordRecovery) {
      if (email.isEmpty || password.isEmpty) {
        showMessage('يرجى إدخال البريد الإلكتروني وكلمة المرور');
        return;
      }

      if (!validateEmail(email)) {
        showMessage('يرجى إدخال بريد إلكتروني صحيح');
        return;
      }
    }

    if (password.isEmpty || password.length < 6) {
      showMessage('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isPasswordRecovery) {
        await AuthService.updatePassword(password: password);

        if (!mounted) return;

        setState(() {
          isPasswordRecovery = false;
          isLogin = true;
          _passwordController.clear();
        });

        showMessage('تم تغيير كلمة المرور بنجاح');

        Navigator.pop(context, true);
      } else if (isLogin) {
        await AuthService.signIn(
          email: email,
          password: password,
        );

        if (!mounted) return;

        Navigator.pop(context, true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AuthService.isAdmin
                  ? 'مرحباً بك في إدارة ShamFlix'
                  : 'تم تسجيل الدخول بنجاح',
            ),
          ),
        );
      } else {
        final message = await AuthService.signUp(
          email: email,
          password: password,
        );

        if (!mounted) return;

        showMessage(message);

        if (AuthService.isLoggedIn) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> signInGoogle() async {
    setState(() {
      isLoading = true;
      _googleSignInPending = true;
    });

    try {
      await AuthService.signInWithGoogle();

      if (!mounted) return;

      showMessage('أكمل تسجيل الدخول عبر Google، وسيتم الرجوع تلقائياً بعد نجاحه.');
    } catch (e) {
      _googleSignInPending = false;
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !validateEmail(email)) {
      showMessage('أدخل بريدك الإلكتروني الصحيح أولاً');
      return;
    }

    setState(() => isLoading = true);

    try {
      await AuthService.sendPasswordReset(email: email);

      if (!mounted) return;

      showMessage(
        'تم إرسال رابط استعادة كلمة المرور. تحقق من بريدك الإلكتروني.',
      );
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = isPasswordRecovery
        ? 'تعيين كلمة مرور جديدة'
        : isLogin
            ? 'سجّل دخولك لمتابعة المشاهدة'
            : 'أنشئ حسابك وانضم إلينا';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: gold,
          elevation: 0,
          title: const Text('حساب ShamFlix'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.movie_creation_outlined,
                    color: gold,
                    size: 75,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'SHAM FLIX',
                    style: TextStyle(
                      color: gold,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 35),

                  if (!isPasswordRecovery) ...[
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: inputDecoration(
                        'البريد الإلكتروني',
                        Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  TextField(
                    controller: _passwordController,
                    obscureText: hidePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: inputDecoration(
                      isPasswordRecovery
                          ? 'كلمة المرور الجديدة'
                          : 'كلمة المرور',
                      Icons.lock_outline,
                    ).copyWith(
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            hidePassword = !hidePassword;
                          });
                        },
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: gold,
                        ),
                      ),
                    ),
                  ),

                  if (isLogin && !isPasswordRecovery) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: isLoading ? null : resetPassword,
                        child: const Text(
                          'نسيت كلمة المرور؟',
                          style: TextStyle(color: gold),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.black,
                            )
                          : Text(
                              isPasswordRecovery
                                  ? 'حفظ كلمة المرور الجديدة'
                                  : isLogin
                                      ? 'تسجيل الدخول'
                                      : 'إنشاء حساب',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  if (!isPasswordRecovery) ...[
                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: isLoading ? null : signInGoogle,
                        icon: const Icon(
                          Icons.g_mobiledata,
                          color: gold,
                          size: 30,
                        ),
                        label: const Text(
                          'المتابعة باستخدام Google',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: gold),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              setState(() {
                                isLogin = !isLogin;
                              });
                            },
                      child: Text(
                        isLogin
                            ? 'ليس لديك حساب؟ أنشئ حساباً جديداً'
                            : 'لديك حساب بالفعل؟ سجّل الدخول',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: gold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: gold),
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: gold),
      ),
    );
  }
}

// آخر تعديل: اعتماد اللون الأحمر وتحديث اسم التطبيق إلى SHAM FLIX في شاشة تسجيل الدخول | التاريخ: 2026-11-21 | الوقت: 20:07:00 بتوقيت تركيا