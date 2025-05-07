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
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String _role = 'user'; // 기본 선택: 사용자

  Future<void> signUp() async {
    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final docRef = FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid);

      // 🔥 FCM 토큰 받아오기
      String? token = await FirebaseMessaging.instance.getToken();

      // Firestore에 기본 정보 및 역할 저장
      await docRef.set({
        'email': emailController.text.trim(),
        'createdAt': Timestamp.now(),
        'role': _role,
        'fcmToken': token ?? '', // fcmToken 추가 저장
      });

      // 역할이 사용자(user)일 때만 healthData 서브컬렉션 생성
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

      Navigator.pop(context); // 로그인 화면으로 돌아가기
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알 수 없는 오류가 발생했어요.')),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: '이메일'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '비밀번호'),
              obscureText: true,
            ),
            const SizedBox(height: 20),

            // ✅ 역할 선택
            const Text('가입 유형 선택', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('사용자'),
                    leading: Radio<String>(
                      value: 'user',
                      groupValue: _role,
                      onChanged: (value) {
                        setState(() {
                          _role = value!;
                        });
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('보호자'),
                    leading: Radio<String>(
                      value: 'guardian',
                      groupValue: _role,
                      onChanged: (value) {
                        setState(() {
                          _role = value!;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: signUp,
              child: const Text('회원가입'),
            ),
          ],
        ),
      ),
    );
  }
}