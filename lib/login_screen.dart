import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'sign_up_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String _humanizeAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return '이메일 형식이 올바르지 않아요.';
      case 'user-disabled':
        return '해당 계정은 사용 중지 상태예요.';
      case 'user-not-found':
        return '등록되지 않은 이메일이에요.';
      case 'wrong-password':
        return '비밀번호가 올바르지 않아요.';
      case 'too-many-requests':
        return '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.';
      case 'network-request-failed':
        return '네트워크 연결을 확인해 주세요.';
      default:
        return '로그인에 실패했어요. 이메일/비밀번호를 확인해 주세요.';
    }
  }

  Future<void> _login() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'fcmToken': token}, SetOptions(merge: true));
          // ignore: avoid_print
          print('✅ 로그인 후 FCM 토큰 업데이트 완료: $token');
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanizeAuthError(e))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알 수 없는 오류가 발생했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseText = Theme.of(context).textTheme;
    final titleStyle = baseText.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final labelStyle = baseText.titleMedium;
    final helpStyle = baseText.bodySmall;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400), // PC/태블릿 대응
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('반가워요 👋', style: titleStyle),
                    const SizedBox(height: 4),
                    Text('로그인하고 건강 상태를 함께 살펴봐요.', style: helpStyle),
                    const SizedBox(height: 24),

                    // 입력 카드
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username, AutofillHints.email],
                                decoration: InputDecoration(
                                  labelText: '이메일',
                                  labelStyle: labelStyle,
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 18),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return '이메일을 입력해 주세요.';
                                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                                  if (!emailRegex.hasMatch(value)) return '올바른 이메일 형식이 아니에요.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              TextFormField(
                                controller: passwordController,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _login(),
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: '비밀번호',
                                  labelStyle: labelStyle,
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 18),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return '비밀번호를 입력해 주세요.';
                                  if (value.length < 6) return '비밀번호는 6자 이상이어야 해요.';
                                  return null;
                                },
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                      : const Text('로그인'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('아직 계정이 없나요? '),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SignUpScreen()),
                            );
                          },
                          child: const Text('회원가입'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    Text(
                      '로그인 문제 시 네트워크 상태를 확인해 주세요.',
                      style: helpStyle?.copyWith(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
