// import 'dart:math';

import 'package:eldercare_app/send_push_notification.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:health/health.dart';
import 'package:android_intent_plus/android_intent.dart';

import 'login_screen.dart';
import 'group_page.dart';
import 'alert_inbox_page.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    requestNotificationPermission();
    setupInteractedMessage();
    saveFcmToken();
    _requestLocationPermission();
    requestHealthPermissions();
  }

  // class _HomeScreenState extends State<HomeScreen> 아래에 추가
  Future<void> requestNotificationPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ 알림 권한 허용됨');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      print('⚠️ 알림이 임시 허용됨');
    } else {
      print('❌ 알림 권한 거부됨');
    }
  }

Future<void> requestHealthPermissions() async {
  final health = Health();
  final types = [HealthDataType.HEART_RATE, HealthDataType.STEPS];
  final permissions = types.map((e) => HealthDataAccess.READ).toList();

  // Health Connect 앱 설치 여부 확인
  final isAvailable = await health.isHealthConnectAvailable();
  if (!isAvailable) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Health Connect 앱이 설치되어 있지 않습니다.')),
    );
    print('❌ Health Connect 앱이 설치되어 있지 않습니다.');
    return;
  }

  // 이미 권한이 있는지 확인 (null-safety)
  bool hasPermissions = (await health.hasPermissions(types, permissions: permissions)) ?? false;
  if (hasPermissions) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이미 건강 데이터 권한이 허용되어 있습니다.')),
    );
    print('✅ 이미 권한 허용됨');
    return;
  }

  // 권한 요청
  bool granted = await health.requestAuthorization(types, permissions: permissions);

  if (granted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 건강 데이터 권한이 허용되었습니다.')),
    );
    print('✅ 권한 허용됨');
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('❌ 건강 데이터 권한이 거부되었습니다.'),
        action: SnackBarAction(
          label: '설정에서 허용',
          onPressed: () {
            openHealthConnectSettings();
          },
        ),
      ),
    );
    print('❌ 권한 거부됨');
  }
}

// Health Connect 설정 화면으로 이동하는 함수
void openHealthConnectSettings() {
  final intent = AndroidIntent(
    action: 'android.settings.HEALTH_CONNECT_SETTINGS',
    package: 'com.google.android.apps.healthdata',
  );
  intent.launch();
}


  void setupInteractedMessage() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'default_channel_id',
              '기본 채널',
              channelDescription: '기본 채널 설명',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });
  }

  Future<void> saveFcmToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
        'fcmToken': token,
      });
      print('✅ FCM 토큰 저장 완료: $token');
    }
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 위치 서비스가 꺼져 있어요. 설정에서 켜 주세요.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 위치 권한이 거부되었어요.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🚫 위치 권한이 영구적으로 거부되었어요. 설정에서 허용해 주세요.')),
      );
      return;
    }

    print('✅ 위치 권한 허용됨');
  }

  Future<String> getAddressFromCoordinates(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
        localeIdentifier: "ko",
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.administrativeArea} ${placemark.locality} ${placemark.subLocality}'.trim();
      } else {
        return '주소를 찾을 수 없음';
      }
    } catch (e) {
      print('❌ 주소 변환 실패: $e');
      return '주소 변환 오류';
    }
  }

  Future<String> _getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    return await getAddressFromCoordinates(position);
  }
  // 기존 saveHealthData 함수를 아래 코드로 교체


  Future<void> saveRealHData() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final role = doc['role'];
  final groupId = doc.data()?['groupId'];

  if (role != 'user') return;

  final health = Health();
  final now = DateTime.now(); 
  final nowKTC = now.toUtc().add(const Duration(hours: 9)); // 한국 시간으로 변환
  final startTime = now.subtract(const Duration(hours: 1)); // 심박수 조회용
  final todayStart = DateTime(nowKTC.year, nowKTC.month, nowKTC.day); // 걸음수 누적 조회용

  try {
    // ✅ 권한 요청
    // final hasPermission = await health.requestAuthorization([
    //   HealthDataType.HEART_RATE,
    //   HealthDataType.STEPS,
    // ]);
    // if (!hasPermission) {
    //   print('❌ 건강 데이터 권한 거부됨');
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('건강 정보 권한이 필요합니다')),
    //   );
    //   return;
    // }

    // ✅ 심박수 데이터 가져오기 (최근 1시간)
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
    // if (steps == 0) {
    //   print('⚠️ 걸음수 데이터 누락');
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('걸음수 데이터를 가져오지 못했습니다')),
    //   );
    //   return;
    // }

    // ✅ 걸음수는 총합으로 정확하게 가져오기 (오늘 하루 기준)
    // final startUTC = todayStart.toUtc();
    // final endUTC = now.toUtc();    
    final steps = await health.getTotalStepsInInterval(
      todayStart,
      nowKTC,
    );
    print(todayStart);
    print(nowKTC);

    // ✅ 위치 정보
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

    // ✅ Firestore 저장
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

    // ✅ 심박수 경고 푸시 알림
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

  // Future<void> saveHealthData() async {
  //   final user = FirebaseAuth.instance.currentUser;
  //   if (user == null) return;
  //
  //   final uid = user.uid;
  //   final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  //   final role = doc['role'];
  //   final groupId = doc.data()?['groupId'];
  //
  //   if (role != 'user') return;
  //
  //   final heartRate = Random().nextInt(80) + 40;
  //   final steps = Random().nextInt(5000) + 1000;
  //
  //   try {
  //     // 📍 현재 위치 + 주소 + 좌표 추출
  //     final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.bestForNavigation);
  //     final address = await getAddressFromCoordinates(position).catchError((e) {
  //       print('❌ 주소 변환 실패: $e');
  //       return '주소 변환 오류';
  //     });
  //
  //     final location = {
  //       'address': address,
  //       'lat': position.latitude,
  //       'lng': position.longitude,
  //     };
  //
  //     await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(uid)
  //         .collection('healthData')
  //         .add({
  //       'heartRate': heartRate,
  //       'steps': steps,
  //       'location': location,
  //       'timestamp': Timestamp.now(),
  //     });
  //
  //     print('✅ 건강 데이터 저장 완료: HR $heartRate, Steps $steps, Location $location');
  //
  //     if ((heartRate > 100 || heartRate < 50) && groupId != null) {
  //       final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
  //       final guardianId = groupDoc['ownerId'];
  //       final groupName = groupDoc['name'];
  //       final guardianDoc = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
  //       final fcmToken = guardianDoc['fcmToken'];
  //
  //       await sendPushNotification(
  //         fcmToken: fcmToken,
  //         title: '🚨 [$groupName] ${user.email}님 심박수 경고',
  //         body: '심박수가 ${heartRate}bpm으로 비정상입니다!',
  //         guardianId: guardianId,
  //         senderEmail: user.email!,
  //         groupName: groupName,
  //       );
  //     }
  //
  //   } catch (e) {
  //     print('❌ saveHealthData 실패: $e');
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('건강 데이터 저장 중 오류가 발생했습니다')),
  //     );
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인 정보를 불러올 수 없습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('홈 화면'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          )
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user!.uid).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final role = userData?['role'] ?? 'user';

          return Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (role == 'guardian')
                    Column(
                      children: [
                        Text('안녕하세요, ${user!.email}님!', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const GroupPage()),
                            );
                          },
                          child: const Text('👥 그룹 페이지로 이동'),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AlertInboxPage()),
                            );
                          },
                          child: const Text('🔔 알림 수신함'),
                        ),
                      ],
                    ),

                  if (role == 'user')
                    Column(
                      children: [
                        Text('안녕하세요, ${user!.email}님!', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 16),
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(user!.uid).get(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const CircularProgressIndicator();

                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            final List<dynamic> invites = data['groupInvites'] ?? [];

                            if (invites.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return Column(
                              children: [
                                const Text('📨 초대된 그룹 목록', style: TextStyle(fontSize: 18)),
                                const SizedBox(height: 10),
                                ...invites.map((groupId) => ListTile(
                                  title: Text('그룹 ID: $groupId'),
                                  trailing: ElevatedButton(
                                    onPressed: () async {
                                      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
                                        'groupId': groupId,
                                        'groupInvites': FieldValue.arrayRemove([groupId]),
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('그룹 가입 완료!')),
                                        );
                                        setState(() {});
                                      }
                                    },
                                    child: const Text('수락'),
                                  ),
                                )),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('healthData').orderBy('timestamp', descending: true).limit(1).snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return Column(
                                children: [
                                  const Text('아직 건강 데이터가 없습니다.'),
                                  // const SizedBox(height: 16),
                                  // ElevatedButton(
                                  //   onPressed: saveHealthData,
                                  //   child: const Text('건강 데이터 저장하기'),
                                  // ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: saveRealHData,
                                    child: const Text('실시간 건강 데이터 저장하기'),
                                  ),
                                ],
                              );
                            }

                            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('🧡 심박수: ${data['heartRate']} bpm'),
                                Text('👟 걸음수: ${data['steps']} 보'),
                                Text(
                                    '📍 위치: ${(data['location'] is Map && data['location'].containsKey('address'))
                                        ? data['location']['address']
                                        : data['location'].toString()}'),
                                Text('🕒 시간: ${data['timestamp'].toDate()}'),
                                // const SizedBox(height: 16),
                                // ElevatedButton(
                                //   onPressed: saveHealthData,
                                //   child: const Text('건강 데이터 저장하기'),
                                // ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: saveRealHData,
                                  child: const Text('실시간 건강 데이터 저장하기'),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const GroupPage()),
                            );
                          },
                          child: const Text('👥 그룹 페이지로 이동'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
