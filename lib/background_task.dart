import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'save_health_data.dart';

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    debugPrint("✅ Firebase 초기화 성공");
  } catch (e) {
    debugPrint("❌ Firebase 초기화 실패: $e");
    // Firebase 없으면 서비스 제대로 못 하니까 종료
    service.stopSelf();
    return;
  }

  debugPrint("🔵 onStart 진입");

  if (service is AndroidServiceInstance) {
    debugPrint("🟢 AndroidServiceInstance 확인");

    try {
      await service.setForegroundNotificationInfo(
        title: "Eldercare 실행 중",
        content: "시연용 건강 데이터를 저장 중입니다",
      );
      debugPrint("🟢 ForegroundNotification 설정 완료");

      await service.setAsForegroundService();
      debugPrint("🟢 setAsForegroundService 호출됨");
    } catch (e) {
      debugPrint("❌ Foreground 설정 실패: $e");
      service.stopSelf();
      return;
    }

    service.on('setAsForeground').listen((event) {
      debugPrint("🟡 수동 Foreground 설정 요청 감지");
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      debugPrint("🟡 수동 Background 설정 요청 감지");
      service.setAsBackgroundService();
    });

    service.on('stopService').listen((event) {
      debugPrint("🔴 stopService 이벤트 감지됨. 서비스 종료 시도");
      service.stopSelf();
    });
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    debugPrint("⏱️ 주기 타이머 시작됨");

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
    debugPrint("✅ [백그라운드] 시연용 데이터 저장 중...");
    await saveAbnormalHDataBackground();
    } else {
      debugPrint("⛔ [백그라운드] 로그인 안됨");
      return;
    }
  });
}

Future<void> stopBackgroundService() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke("stopService");
    debugPrint("✅ 백그라운드 서비스 종료됨");
  }
}
