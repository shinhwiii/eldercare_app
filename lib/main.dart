import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Background service 관련 패키지
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'dart:async';

import 'login_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Firebase 초기화
  runApp(const MyApp());
}
// Background service 설정
// 🔸 백그라운드 핸들러 (이 함수는 context 등 사용 X)
// @pragma('vm:entry-point')
// void onStart(ServiceInstance service) async {
//   DartPluginRegistrant.ensureInitialized();

//   service.on('setAsForeground').listen((event) {
//     service.setAsForegroundService();
//   });

//   service.on('setAsBackground').listen((event) {
//     service.setAsBackgroundService();
//   });

//   Timer.periodic(const Duration(minutes: 15), (timer) async {
//     await saveRealHData(); // 내부에서 user == null 체크 포함됨
//   });
// }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eldercare App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true, // 최신 스타일 사용 (선택)
      ),

      // ✅ 자동 로그인 상태 감지 및 분기
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 🔄 Firebase 초기 연결 중일 때 로딩 표시
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // ✅ 로그인된 상태 → 홈 화면으로 이동
          if (snapshot.hasData) {
            return const HomeScreen();
          }

          // ❌ 로그인 안 된 상태 → 로그인 화면으로 이동
          return const LoginScreen();
        },
      ),
    );
  }
}
