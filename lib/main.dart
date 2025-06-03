import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Background service 관련 패키지
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'dart:async';

import 'save_health_data.dart';
import 'login_screen.dart';
import 'home_screen.dart';


// // Background service 설정
// Future<void> initializeService() async {
//   final service = FlutterBackgroundService();

//   await service.configure(
//     androidConfiguration: AndroidConfiguration(
//       onStart: onStart, // 서비스 시작 시 실행할 함수
//       isForegroundMode: true,
//       autoStart: true, // 앱 실행 시 자동 시작
//       notificationChannelId: 'my_channel',
//       initialNotificationTitle: 'Eldercare Service',
//       initialNotificationContent: '데이터 모니터링 중...',
//     ),
//     iosConfiguration: IosConfiguration(
//       onForeground: onStart,
//       onBackground: backgroundHandler,
//     ),
//   );

//   await service.startService();
// }

// Future<bool> backgroundHandler(ServiceInstance service) async {
//   DartPluginRegistrant.ensureInitialized();
//   // 백그라운드 시 처리할 로직 (예: Firebase 초기화 등)
//   return true;
// }


// @pragma('vm:entry-point')
// void onStart(ServiceInstance service) async {
//   DartPluginRegistrant.ensureInitialized();

//   Timer.periodic(const Duration(seconds: 10), (timer) async {
//     final user = FirebaseAuth.instance.currentUser;
//     if (user != null) {
//       await saveRealHDataBackground();
//     } else {
//       timer.cancel();
//     }
//   });
// }


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Firebase 초기화
  // await initializeService(); // Background service 초기화
  runApp(const MyApp());
}


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
