import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // ===== 상태 & 컨트롤러 =====
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();   // 사용자 전용
  final phoneController = TextEditingController();  // 공통

  String _role = 'user'; // 기본: 사용자
  bool _isLoading = false;
  bool _obscure = true;

  // ===== 유틸 =====
  // 전화번호 간단 정규화: 010xxxx → +8210xxxx
  String _normKR(String input) {
    var d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '';
    if (d.startsWith('0')) d = '82${d.substring(1)}';
    return '+$d';
  }

  bool _isValidPhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 9;
  }

  // ===== 회원가입 로직 (기능 유지) =====
  Future<void> signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      // 프리체크 (원래 로직 유지)
      final email = emailController.text.trim();
      final password = passwordController.text.trim();
      final phoneRaw = phoneController.text.trim();

      if (_role == 'user' && nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름을 입력해주세요.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Auth 생성
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

      // FCM 토큰
      final token = await FirebaseMessaging.instance.getToken();

      // 저장 데이터 (원래 키 유지)
      final data = <String, dynamic>{
        'email': email,
        'createdAt': Timestamp.now(),
        'role': _role,
        'fcmToken': token ?? '',
        'phone': _normKR(phoneRaw),
      };
      if (_role == 'user') {
        data['name'] = nameController.text.trim();
        data['guardianUid'] = null;
      }

      await docRef.set(data, SetOptions(merge: true));

      // 사용자만 healthData 초기 문서 생성(원래 로직 유지)
      if (_role == 'user') {
        await docRef.collection('healthData').doc('init').set({
          'heartRate': 0,
          'steps': 0,
          'location': '0,0',
          'timestamp': Timestamp.now(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입이 완료되었습니다.')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = '이미 등록된 이메일이에요.';
          break;
        case 'invalid-email':
          message = '이메일 형식이 잘못됐어요.';
          break;
        case 'weak-password':
          message = '비밀번호는 최소 6자 이상이어야 해요.';
          break;
        case 'network-request-failed':
          message = '네트워크 연결을 확인해 주세요.';
          break;
        default:
          message = '회원가입 실패: ${e.message}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알 수 없는 오류가 발생했어요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
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
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('처음 오셨군요 👋', style: titleStyle),
                    const SizedBox(height: 4),
                    Text('간단한 정보만 입력하면 회원가입이 완료돼요.', style: helpStyle),
                    const SizedBox(height: 24),

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
                              // 이메일
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

                              // 비밀번호 + 토글
                              TextFormField(
                                controller: passwordController,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.newPassword],
                                decoration: InputDecoration(
                                  labelText: '비밀번호 (6자 이상)',
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
                                  if (value.length < 6) return '비밀번호는 최소 6자 이상이어야 해요.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // 역할 선택 (사용자 / 보호자)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('가입 유형 선택', style: labelStyle?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'user', label: Text('사용자'), icon: Icon(Icons.person_outline)),
                                  ButtonSegment(value: 'guardian', label: Text('보호자'), icon: Icon(Icons.shield_outlined)),
                                ],
                                selected: {_role},
                                onSelectionChanged: (s) => setState(() => _role = s.first),
                                showSelectedIcon: false,
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  shape: MaterialStatePropertyAll(
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 공통: 전화번호
                              TextFormField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: _role == 'user' ? TextInputAction.next : TextInputAction.done,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                decoration: InputDecoration(
                                  labelText: '전화번호 (예: 01012345678)',
                                  labelStyle: labelStyle,
                                  prefixIcon: const Icon(Icons.phone_outlined),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 18),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return '전화번호를 입력해 주세요.';
                                  if (!_isValidPhone(value)) return '전화번호를 정확히 입력해 주세요.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // 사용자만: 이름
                              if (_role == 'user') ...[
                                TextFormField(
                                  controller: nameController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: '이름',
                                    labelStyle: labelStyle,
                                    prefixIcon: const Icon(Icons.badge_outlined),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 18),
                                  validator: (v) {
                                    final value = (v ?? '').trim();
                                    if (_role == 'user' && value.isEmpty) return '이름을 입력해 주세요.';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                              ],

                              const SizedBox(height: 8),
                              // 가입 버튼
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : signUp,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                      : const Text('회원가입'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      '입력하신 전화번호는 계정 식별과 알림에 사용돼요.',
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
