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
  // 기본 입력
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String _role = 'user'; // 기본: 사용자

  // 추가 입력
  final nameController = TextEditingController();   // 사용자만 표시/필수
  final phoneController = TextEditingController();  // 공통(사용자/보호자) 필수

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

  Future<void> signUp() async {
    try {
      // ===== 프리체크 =====
      final email = emailController.text.trim();
      final password = passwordController.text.trim();
      final phoneRaw = phoneController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일/비밀번호를 입력해주세요.')),
        );
        return;
      }
      if (!_isValidPhone(phoneRaw)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('전화번호를 정확히 입력해주세요.')),
        );
        return;
      }
      if (_role == 'user' && nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름을 입력해주세요.')),
        );
        return;
      }

      // ===== Auth 생성 =====
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

      // FCM 토큰
      final token = await FirebaseMessaging.instance.getToken();

      // ===== 저장 데이터 =====
      final data = <String, dynamic>{
        'email': email,
        'createdAt': Timestamp.now(),
        'role': _role,
        'fcmToken': token ?? '',
        'phone': _normKR(phoneRaw), // 공통: 본인 전화
      };
      if (_role == 'user') {
        data['name'] = nameController.text.trim(); // 사용자만 이름
        data['guardianUid'] = null;                // 이후 그룹 초대-수락 시 매핑
      }

      await docRef.set(data, SetOptions(merge: true));

      // 사용자만 healthData 초기 문서 생성(기존 로직 유지)
      if (_role == 'user') {
        await docRef.collection('healthData').doc('init').set({
          'heartRate': 0,
          'steps': 0,
          'location': '0,0',
          'timestamp': Timestamp.now(),
        });
      }

      if (!context.mounted) return;
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
        default:
          message = '회원가입 실패: ${e.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알 수 없는 오류가 발생했어요.')),
      );
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
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 이메일/비밀번호
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: '이메일'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: '비밀번호'),
                obscureText: true,
              ),
              const SizedBox(height: 20),

              // 역할 선택
              const Text('가입 유형 선택', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('사용자'),
                      leading: Radio<String>(
                        value: 'user',
                        groupValue: _role,
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: const Text('보호자'),
                      leading: Radio<String>(
                        value: 'guardian',
                        groupValue: _role,
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ),
                  ),
                ],
              ),

              const Divider(height: 32),

              // 공통: 본인 전화번호
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: '전화번호 (예: 01012345678)',
                ),
                keyboardType: TextInputType.phone,
              ),

              // 사용자만: 이름
              if (_role == 'user') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '이름'),
                  textCapitalization: TextCapitalization.words,
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: signUp,
                  child: const Text('회원가입'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
