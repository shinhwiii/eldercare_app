import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart';
import 'package:flutter/material.dart';

import 'send_push_notification.dart';

typedef AddressResolver = Future<String> Function(Position position);

Future<void> saveRealHData({
  required BuildContext context,
  required AddressResolver getAddressFromCoordinates,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final role = doc['role'];
  final groupId = doc.data()?['groupId'];

  if (role != 'user') return;

  final health = Health();
  final now = DateTime.now();
  final nowKTC = now.toUtc().add(const Duration(hours: 9));
  final startTime = now.subtract(const Duration(hours: 1));
  final todayStart = DateTime(nowKTC.year, nowKTC.month, nowKTC.day);

  try {
    final heartData = await health.getHealthDataFromTypes(
      startTime: startTime,
      endTime: now,
      types: [HealthDataType.HEART_RATE],
    );

    int? heartRate;
    for (var data in heartData) {
      if (data.value is NumericHealthValue &&
          data.type == HealthDataType.HEART_RATE) {
        heartRate = (data.value as NumericHealthValue).numericValue.toInt();
      }
    }

    if (heartRate == null) {
      print('⚠️ 심박수 데이터 없음');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('심박수 데이터를 가져올 수 없습니다')),
      );
      return;
    }

    final steps = await health.getTotalStepsInInterval(
      todayStart,
      nowKTC,
    );

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    String address = await getAddressFromCoordinates(position).catchError((e) {
      print('❌ 주소 변환 실패: $e');
      return '주소 변환 오류';
    });

    Map<String, dynamic> location = {
      'address': address,
      'lat': position.latitude,
      'lng': position.longitude,
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('healthData')
        .add({
      'heartRate': heartRate,
      'steps': steps,
      'location': location,
      'timestamp': Timestamp.now(),
    });

    print('✅ 건강 데이터 저장 완료: HR $heartRate, Steps $steps');

    if ((heartRate > 100 || heartRate < 50) && groupId != null) {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      final guardianId = groupDoc['ownerId'];
      final groupName = groupDoc['name'];
      final guardianDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(guardianId)
          .get();
      final fcmToken = guardianDoc['fcmToken'];

      await sendPushNotification(
        fcmToken: fcmToken,
        title: '🚨 [$groupName] ${user.email}님 심박수 경고',
        body: '심박수가 ${heartRate}bpm으로 비정상입니다!',
        guardianId: guardianId,
        senderEmail: user.email!,
        groupName: groupName,
        abnormalUserId: uid,
      );
    }
  } catch (e, stackTrace) {
    print('''
⚠️ 치명적 오류 발생
Error: $e
Stack Trace: $stackTrace
''');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('건강 데이터 처리 중 오류가 발생했습니다')),
    );
  }
}

// 백그라운드용 함수
Future<void> saveRealHDataBackground() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final role = doc['role'];
  final groupId = doc.data()?['groupId'];

  if (role != 'user') return;

  final health = Health();
  final now = DateTime.now();
  final nowKTC = now.toUtc().add(const Duration(hours: 9));
  final startTime = now.subtract(const Duration(hours: 1));
  final todayStart = DateTime(nowKTC.year, nowKTC.month, nowKTC.day);

  try {
    final heartData = await health.getHealthDataFromTypes(
      startTime: startTime,
      endTime: now,
      types: [HealthDataType.HEART_RATE],
    );

    int? heartRate;
    for (var data in heartData) {
      if (data.value is NumericHealthValue &&
          data.type == HealthDataType.HEART_RATE) {
        heartRate = (data.value as NumericHealthValue).numericValue.toInt();
      }
    }

    if (heartRate == null) {
      print('⚠️ 심박수 데이터 없음');
      return;
    }

    final steps = await health.getTotalStepsInInterval(
      todayStart,
      nowKTC,
    );

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    // 주소 변환 직접 처리
    String address = '주소 변환 오류';
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
        localeIdentifier: "ko",
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        address = '${placemark.administrativeArea} ${placemark.locality} ${placemark.subLocality}'.trim();
      }
    } catch (e) {
      print('❌ 주소 변환 실패: $e');
    }

    Map<String, dynamic> location = {
      'address': address,
      'lat': position.latitude,
      'lng': position.longitude,
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('healthData')
        .add({
      'heartRate': heartRate,
      'steps': steps,
      'location': location,
      'timestamp': Timestamp.now(),
    });

    print('✅ [백그라운드] 건강 데이터 저장 완료: HR $heartRate, Steps $steps');

    if ((heartRate > 100 || heartRate < 50) && groupId != null) {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      final guardianId = groupDoc['ownerId'];
      final groupName = groupDoc['name'];
      final guardianDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(guardianId)
          .get();
      final fcmToken = guardianDoc['fcmToken'];

      await sendPushNotification(
        fcmToken: fcmToken,
        title: '🚨 [$groupName] ${user.email}님 심박수 경고',
        body: '심박수가 ${heartRate}bpm으로 비정상입니다!',
        guardianId: guardianId,
        senderEmail: user.email!,
        groupName: groupName,
        abnormalUserId: uid,
      );
    }
  } catch (e, stackTrace) {
    print('''
⚠️ [백그라운드] 치명적 오류 발생
Error: $e
Stack Trace: $stackTrace
''');
  }
}

Future<void> saveAbnormalHDataBackground() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final role = doc['role'];
  final groupId = doc.data()?['groupId'];

  if (role != 'user') return;

  final random = Random();
  int heartRate = random.nextBool() ? random.nextInt(40) + 30 : random.nextInt(40) + 101;
  int steps = random.nextInt(2000) + 1000;

  try {
    // 🔵 위치 가져오기
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    // 🔵 주소 변환
    String address = '주소 변환 오류';
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
        localeIdentifier: "ko",
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        address = '${placemark.administrativeArea} ${placemark.locality} ${placemark.subLocality}'.trim();
      }
    } catch (e) {
      print('❌ 주소 변환 실패: $e');
    }

    Map<String, dynamic> location = {
      'address': address,
      'lat': position.latitude,
      'lng': position.longitude,
    };

    // 🔴 비정상 데이터 저장
    await FirebaseFirestore.instance.collection('users').doc(uid).collection('healthData').add({
      'heartRate': heartRate,
      'steps': steps,
      'location': location, // 추가됨
      'timestamp': Timestamp.now(),
    });

    print('✅ [백그라운드] 테스트용 비정상 심박수 저장 완료: HR $heartRate, Steps $steps');

    // 🔴 푸시 알림
    if ((heartRate > 100 || heartRate < 50) && groupId != null) {
      final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
      final guardianId = groupDoc['ownerId'];
      final groupName = groupDoc['name'];
      final guardianDoc = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
      final fcmToken = guardianDoc['fcmToken'];

      await sendPushNotification(
        fcmToken: fcmToken,
        title: '🚨 [$groupName] ${user.email}님 심박수 경고',
        body: '심박수가 ${heartRate}bpm으로 비정상입니다!',
        guardianId: guardianId,
        senderEmail: user.email!,
        groupName: groupName,
        abnormalUserId: uid,
      );
    }
  } catch (e, stackTrace) {
    print('''
⚠️ [백그라운드] saveAbnormalHDataBackground 오류 발생
Error: $e
Stack Trace: $stackTrace
''');
  }
}

/// =========================
/// ✅ 낙상 감지 시: 심박/걸음/위치 수집→저장→푸시 (백그라운드용)
///     * 평소엔 낙상만 감시하다가, 낙상 확정 순간에만 호출해서 수집/저장/알림 처리.
///     * 수집 로직과 저장 구조는 saveRealHDataBackground와 동일.
/// =========================
Future<void> saveFallDataBackground() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final role = doc['role'];
  final groupId = doc.data()?['groupId'];

  if (role != 'user') return;

  final health = Health();
  final now = DateTime.now();
  final nowKTC = now.toUtc().add(const Duration(hours: 9));
  final startTime = now.subtract(const Duration(hours: 1));
  final todayStart = DateTime(nowKTC.year, nowKTC.month, nowKTC.day);

  try {
    // ▶ 심박수 (saveRealHDataBackground와 동일 구간/방식)
    final heartData = await health.getHealthDataFromTypes(
      startTime: startTime,
      endTime: now,
      types: [HealthDataType.HEART_RATE],
    );

    int? heartRate;
    for (var data in heartData) {
      if (data.value is NumericHealthValue &&
          data.type == HealthDataType.HEART_RATE) {
        heartRate = (data.value as NumericHealthValue).numericValue.toInt();
      }
    }

    // ▶ 걸음수 (동일: 오늘 00시(KST) ~ 지금)
    final steps = await health.getTotalStepsInInterval(
      todayStart,
      nowKTC,
    );

    // ▶ 위치 + 주소 (동일)
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    String address = '주소 변환 오류';
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
        localeIdentifier: "ko",
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        address = '${placemark.administrativeArea} ${placemark.locality} ${placemark.subLocality}'.trim();
      }
    } catch (e) {
      print('❌ [낙상] 주소 변환 실패: $e');
    }

    Map<String, dynamic> location = {
      'address': address,
      'lat': position.latitude,
      'lng': position.longitude,
    };

    // ▶ Firestore 저장 (구조 동일 + fallDetected: true)
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('healthData')
        .add({
      'fallDetected': true,
      'heartRate': heartRate,
      'steps': steps,
      'location': location,
      'timestamp': Timestamp.now(),
    });

    print('✅ [백그라운드][낙상] 저장 완료: HR $heartRate, Steps $steps');

    // ▶ 보호자 푸시 (심박 포함 문구, HR 없으면 생략)
    if (groupId != null) {
      final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
      final guardianId = groupDoc['ownerId'];
      final groupName = groupDoc['name'];
      final guardianDoc = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
      final fcmToken = guardianDoc['fcmToken'];

      final hrText = (heartRate != null) ? ' 심박수: ${heartRate}bpm' : '';
      await sendPushNotification(
        fcmToken: fcmToken,
        title: '🚨 [$groupName] ${user.email}님 낙상 감지',
        body: '낙상이 감지되었습니다.$hrText',
        guardianId: guardianId,
        senderEmail: user.email ?? '',
        groupName: groupName,
        abnormalUserId: uid,
      );
    }
  } catch (e, stackTrace) {
    print('''
⚠️ [백그라운드][낙상] saveFallDataBackground 오류 발생
Error: $e
Stack Trace: $stackTrace
''');
  }
}

/// (기존) 낙상 알림만 보내는 헬퍼 — 기존 코드에서 사용 중이면 유지
Future<void> sendFallAlertBackground() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    print('⚠️ [낙상] 로그인 사용자 없음');
    return;
  }

  try {
    final uid = user.uid;

    // 사용자 문서
    final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!userSnap.exists) {
      print('⚠️ [낙상] 사용자 문서 없음');
      return;
    }

    final data = userSnap.data()!;
    if (data['role'] != 'user') {
      print('ℹ️ [낙상] 보호자 계정은 푸시 전송 안 함');
      return;
    }

    final String? groupId = data['groupId'];
    if (groupId == null) {
      print('⚠️ [낙상] groupId 없음');
      return;
    }

    // 그룹/보호자 문서
    final groupSnap = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
    if (!groupSnap.exists) {
      print('⚠️ [낙상] 그룹 문서 없음');
      return;
    }
    final String guardianId = groupSnap['ownerId'];
    final String groupName  = groupSnap.data()?['name'] ?? '그룹';

    final guardianSnap = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
    if (!guardianSnap.exists) {
      print('⚠️ [낙상] 보호자 문서 없음');
      return;
    }
    final String? fcmToken = guardianSnap.data()?['fcmToken'];
    if (fcmToken == null || fcmToken.isEmpty) {
      print('⚠️ [낙상] 보호자 FCM 토큰 없음');
      return;
    }

    await sendPushNotification(
      fcmToken: fcmToken,
      title: '🚨 [$groupName] ${user.email ?? '사용자'} 낙상 감지',
      body: '낙상이 감지되었습니다. 즉시 안전 확인이 필요합니다.',
      guardianId: guardianId,
      senderEmail: user.email ?? '',
      groupName: groupName,
      abnormalUserId: uid,
    );

    print('✅ [낙상] 보호자에게 푸시 전송 완료');
  } catch (e, st) {
    print('''
⛔ [낙상] sendFallAlertBackground 오류
Error: $e
Stack Trace: $st
''');
  }
}
