import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:permission_handler/permission_handler.dart'; // ✅ 알림 권한 요청용

import 'save_health_data.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'background_task.dart'; // ✅ 따로 만든 onStart 사용

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();            // ✅ Firebase 초기화
  await requestNotificationPermission();     // ✅ 알림 권한 요청
  runApp(const MyApp());
}

/// ✅ Android 13+ 알림 권한 요청
Future<void> requestNotificationPermission() async {
  await [
    Permission.notification,
    Permission.activityRecognition,
    Permission.sensors,
  ].request();
}

/// ✅ Background service 초기화 함수
Future<void> initializeService() async {
  debugPrint("rr");
  final service = FlutterBackgroundService();

  // ✅ 이미 실행 중이면 재시작하지 않음
  final isRunning = await service.isRunning();
  if (isRunning) {
    debugPrint("🟡 백그라운드 서비스가 이미 실행 중입니다. 초기화 건너뜀.");
    return;
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // ✅ background_task.dart에서 정의
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: 'eldercare_channel_id',
      initialNotificationTitle: 'Eldercare 서비스 실행 중',
      initialNotificationContent: '건강 데이터를 주기적으로 저장하고 있어요',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: backgroundHandler,
    ),
  );

  await service.startService();
}

/// iOS 백그라운드 핸들러
Future<bool> backgroundHandler(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
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
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return const HomeScreen();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}
