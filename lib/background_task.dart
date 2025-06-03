import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';

import 'save_health_data.dart'; // 
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // ✅ foreground service로 설정 (시작 시 반드시 필요함)
    await service.setAsForegroundService();

    // 선택적으로 foreground/background 전환 리스너
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // 🕒 주기적 백그라운드 작업 실행
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    // foreground 상태 확인 (필요 시 작업 생략)
    if (service is AndroidServiceInstance && !(await service.isForegroundService())) {
      return;
    }

    await saveRealHDataBackground(); // 실질적 작업 수행
  });
}

Future<void> stopBackgroundService() async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (isRunning) {
    service.invoke("stopService");
    debugPrint("✅ 백그라운드 서비스 종료됨");
  }
}