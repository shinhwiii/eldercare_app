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