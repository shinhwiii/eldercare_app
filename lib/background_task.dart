import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'save_health_data.dart';
import 'fall_detector.dart';

/// 전역: 낙상 감지기 인스턴스 및 시작 여부 플래그
FallDetector? _fallDetector;
bool _fallStarted = false;

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
      debugPrint("🟡 수동 Foreground q설정 요청 감지");
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      debugPrint("🟡 수동 Background 설정 요청 감지");
      service.setAsBackgroundService();
    });

    service.on('stopService').listen((event) async {
      debugPrint("🔴 stopService 이벤트 감지됨. 서비스 종료 시도");
      // 👉 낙상 감지 정지
      await _fallDetector?.stop();
      _fallDetector = null;
      _fallStarted = false;

      service.stopSelf();
    });
  }

  // 주기 작업 + 최초 한 번 낙상 감지 시작(사용자/역할 확인 후)
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    debugPrint("⏱️ 주기 타이머 시작됨");

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // ===== 1) 낙상 감지 시작(한 번만) =====
      if (!_fallStarted) {
        try {
          final uid = user.uid;
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

          if (userDoc.exists && userDoc.data()?['role'] == 'user') {
            _fallDetector ??= FallDetector(
              // ✅ 테스트 모드: 웨어러블 없이도 동작하도록
              //    낙상 확정 시 "푸시 알림만" 전송 (심박/걸음/위치 수집 없음)
              onFall: () async {
                try {
                  await sendFallAlertBackground(); // saveFallDataBackground();로 바꾸기
                  debugPrint("✅ [낙상-테스트] 푸시 발송 완료");
                } catch (e, st) {
                  debugPrint("❌ [낙상-테스트] 처리 중 오류: $e\n$st");
                }
              },
              // 필요 시 민감도 조절(테스트에 민감하게 하려면 수치 낮추거나/높임)
              freeFallG: 0.5,     // 낙하 감지
              impactG: 2.5,       // 충격 감지
              immobileMs: 7000,   // 떨어진 후 정지 시간
              cooldownMs: 60000,  // 알람 보낸 후 쿨타임
            )..start();

            _fallStarted = true;
            debugPrint("✅ 낙상 감지 시작됨");
          } else {
            debugPrint("ℹ️ 사용자 역할이 'user'가 아니므로 낙상 감지 시작 안 함");
          }
        } catch (e, st) {
          debugPrint("❌ 낙상 감지 시작 실패: $e\n$st");
        }
      }

      // ===== 2) 기존 시연용 데이터 저장 =====
      debugPrint("✅ [백그라운드] 시연용 데이터 저장 중...");
      await saveRealHDataBackground();
    } else {
      debugPrint("⛔ [백그라운드] 로그인 안됨");
      return;
    }
  });
}

Future<void> stopBackgroundService() async {
  // 👉 낙상 감지 정지
  await _fallDetector?.stop();
  _fallDetector = null;
  _fallStarted = false;

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke("stopService");
    debugPrint("✅ 백그라운드 서비스 종료됨");
  }
}
