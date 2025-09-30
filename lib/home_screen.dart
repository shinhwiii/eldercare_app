import 'dart:math';
import 'dart:ui';

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
import 'package:flutter_background_service/flutter_background_service.dart';

import 'background_task.dart';
import 'main.dart';
import 'save_health_data.dart';
import 'login_screen.dart';
import 'group_page.dart';
import 'alert_inbox_page.dart';
import 'group_detail_page.dart'; // ✅ 그룹 상세 페이지로 이동

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
    _startServiceIfNeeded();
  }

  Future<void> _startServiceIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final role = doc['role'];

    if (role != 'user') return; // 👈 보호자는 실행 안 함

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await initializeService(); // 👈 background_task.dart에 정의된 configure & start 포함 함수
      // ignore: avoid_print
      print("✅ 사용자로 로그인됨. 백그라운드 서비스 시작됨");
    }
  }

  Future<void> requestNotificationPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // ignore: avoid_print
      print('✅ 알림 권한 허용됨');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      // ignore: avoid_print
      print('⚠️ 알림이 임시 허용됨');
    } else {
      // ignore: avoid_print
      print('❌ 알림 권한 거부됨');
    }
  }

  Future<void> requestHealthPermissions() async {
    final health = Health();
    final types = [HealthDataType.HEART_RATE, HealthDataType.STEPS];
    final permissions = types.map((e) => HealthDataAccess.READ).toList();

    final isAvailable = await health.isHealthConnectAvailable();
    if (!isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Health Connect 앱이 설치되어 있지 않습니다.')),
      );
      // ignore: avoid_print
      print('❌ Health Connect 앱이 설치되어 있지 않습니다.');
      return;
    }

    bool hasPermissions = (await health.hasPermissions(types, permissions: permissions)) ?? false;
    if (hasPermissions) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 건강 데이터 권한이 허용되어 있습니다.')),
      );
      // ignore: avoid_print
      print('✅ 이미 권한 허용됨');
      return;
    }

    bool granted = await health.requestAuthorization(types, permissions: permissions);
    if (granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 건강 데이터 권한이 허용되었습니다.')),
      );
      // ignore: avoid_print
      print('✅ 권한 허용됨');
    } else {
      if (!mounted) return;
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
      // ignore: avoid_print
      print('❌ 권한 거부됨');
    }
  }

  void openHealthConnectSettings() {
    final intent = AndroidIntent(
      action: 'android.settings.HEALTH_CONNECT_SETTINGS',
      package: 'com.google.android.apps.healthdata',
    );
    intent.launch();
  }

  Future<void> setupInteractedMessage() async {
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
      // ignore: avoid_print
      print('✅ FCM 토큰 저장 완료: $token');
    }
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 위치 서비스가 꺼져 있어요. 설정에서 켜 주세요.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 위치 권한이 거부되었어요.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🚫 위치 권한이 영구적으로 거부되었어요. 설정에서 허용해 주세요.')),
      );
      return;
    }

    // ignore: avoid_print
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
      // ignore: avoid_print
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

  Future<void> saveAbnormalHData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // ignore: avoid_print
      print('⛔ [TEST] user == null');
      return;
    }

    final uid = user.uid;
    // ignore: avoid_print
    print('🔎 [TEST] uid=$uid, email=${user.email}');

    try {
      // 1) 사용자 문서/역할/그룹
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) {
        // ignore: avoid_print
        print('⛔ [TEST] users/$uid 문서 없음');
        return;
      }
      final data = snap.data()!;
      final role = data['role'];
      final groupId = data['groupId'];
      // ignore: avoid_print
      print('🔎 [TEST] role=$role, groupId=$groupId');

      if (role != 'user') {
        // ignore: avoid_print
        print('ℹ️ [TEST] role!=user → 중단');
        return;
      }
      if (groupId == null) {
        // ignore: avoid_print
        print('⛔ [TEST] groupId 없음(그룹 미가입)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('그룹에 가입되어 있지 않습니다. 먼저 그룹에 가입해 주세요.')),
          );
        }
        return;
      }

      // 2) 표시용 이름: name → 이메일 앞부분 → '회원'
      String displayName;
      final name = (data['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        displayName = name;
      } else if ((user.email ?? '').isNotEmpty) {
        displayName = user.email!.split('@').first;
      } else {
        displayName = '회원';
      }
      // ignore: avoid_print
      print('🔎 [TEST] displayName=$displayName');

      // 3) 테스트용 비정상 심박/걸음 생성
      final random = Random();
      final int heartRate = random.nextBool() ? (random.nextInt(40) + 10) : (random.nextInt(40) + 101); // 30~69 or 100~149
      final steps = random.nextInt(2000) + 1000;
      // ignore: avoid_print
      print('🔎 [TEST] HR=$heartRate, steps=$steps');

      // 4) 위치 + 주소(실패 허용)
      String address = '주소 변환 오류';
      double? lat, lng;
      try {
        final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.bestForNavigation);
        lat = position.latitude;
        lng = position.longitude;
        address = await getAddressFromCoordinates(position).catchError((e) {
          // ignore: avoid_print
          print('❌ [TEST] 주소 변환 실패: $e');
          return '주소 변환 오류';
        });
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ [TEST] 위치 가져오기 실패: $e');
      }

      final location = {
        'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

      // 5) 데이터 저장
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('healthData')
          .add({
        'heartRate': heartRate,
        'steps': steps,
        'location': location,
        'timestamp': Timestamp.now(),
        'source': 'TEST_BUTTON',
      });
      // ignore: avoid_print
      print('✅ [TEST] 비정상 데이터 저장 완료');

      // 6) 기준 충족 여부 확인
      final isAbnormal = (heartRate > 100 || heartRate < 50);
      // ignore: avoid_print
      print('🔎 [TEST] isAbnormal=$isAbnormal');
      if (!isAbnormal) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('정상 값으로 생성되어 알림 미전송 (HR=$heartRate)')),
          );
        }
        return;
      }

      // 7) 그룹/보호자/토큰
      final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        // ignore: avoid_print
        print('⛔ [TEST] groups/$groupId 문서 없음');
        return;
      }
      final guardianId = groupDoc['ownerId'];
      final groupName = groupDoc['name'];
      // ignore: avoid_print
      print('🔎 [TEST] guardianId=$guardianId, groupName=$groupName');

      final guardianDoc = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
      if (!guardianDoc.exists) {
        // ignore: avoid_print
        print('⛔ [TEST] guardian users/$guardianId 문서 없음');
        return;
      }
      final fcmToken = (guardianDoc['fcmToken'] as String?) ?? '';
      // ignore: avoid_print
      print('🔎 [TEST] guardian fcmToken length=${fcmToken.length}');
      if (fcmToken.isEmpty) {
        // ignore: avoid_print
        print('⛔ [TEST] 보호자 FCM 토큰 비어 있음');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('보호자 기기의 알림 토큰이 없습니다. 보호자 앱에서 로그인해 주세요.')),
          );
        }
        return;
      }

      // 8) 푸시 전송(이름 기반 + 수신함 이름 표시)
      await sendPushNotification(
        fcmToken: fcmToken,
        title: '🚨 [$groupName] $displayName님 심박수 경고',
        body: '심박수가 ${heartRate}bpm으로 비정상입니다!',
        guardianId: guardianId,
        senderEmail: user.email ?? '',
        senderName: displayName, // ✅ 수신함에도 이름으로 저장됨
        groupName: groupName,
        abnormalUserId: uid,
      );

      // ignore: avoid_print
      print('✅ [TEST] sendPushNotification 호출 완료');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비정상 테스트: 알림 전송 시도 완료 (로그 확인)')),
      );
    } catch (e) {
      // ignore: avoid_print
      print('❌ [TEST] saveAbnormalHData 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('건강 데이터 저장/알림 처리 중 오류가 발생했습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인 정보를 불러올 수 없습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              FlutterBackgroundService().invoke("stopService");
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

          // ✅ 이름/표시명 계산: 사용자일 때 name 사용, 없으면 '회원'
          final name = (userData?['name'] as String?)?.trim();
          final displayName = (name != null && name.isNotEmpty) ? name : '회원';

          // ✅ 초대 목록은 이미 불러온 userData 재사용
          final List<dynamic> invites = (userData?['groupInvites'] ?? []) as List<dynamic>;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===== 공통 헤더 =====
                    Text(
                      role == 'guardian' ? '안녕하세요 👋' : '안녕하세요, $displayName님! 👋',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),

                    // ===== 보호자 홈 =====
                    if (role == 'guardian') ...[
                      // 1) 요약/관리 카드 (타일 탭 가능)
                      _SectionCard(
                        title: '관리',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('그룹과 알림을 한 곳에서 관리하세요.', style: TextStyle(fontSize: 16)),
                            const SizedBox(height: 12),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('groups')
                                  .where('ownerId', isEqualTo: user!.uid)
                                  .snapshots(),
                              builder: (context, snap) {
                                final cnt = (snap.hasData) ? snap.data!.docs.length : 0;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _StatTile(
                                        label: '내 그룹',
                                        value: '$cnt개',
                                        icon: Icons.group_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => const GroupPage()),
                                          ).then((_) => setState(() {}));
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _StatTile(
                                        label: '알림 수신함',
                                        value: '확인하기',
                                        icon: Icons.notifications_none,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => const AlertInboxPage()),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _PrimaryButton(
                              text: '🔔 알림 수신함 열기',
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertInboxPage()));
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 2) 내 그룹 리스트 카드 (탭 → GroupDetailPage(groupId, groupName))
                      _SectionCard(
                        title: '내 그룹',
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('groups')
                              .where('ownerId', isEqualTo: user!.uid)
                              .orderBy('createdAt', descending: true)
                              .snapshots(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (!snap.hasData || snap.data!.docs.isEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('아직 생성한 그룹이 없어요.', style: TextStyle(fontSize: 16)),
                                  const SizedBox(height: 12),
                                  _PrimaryButton(
                                    text: '➕ 새 그룹 만들기',
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupPage()));
                                    },
                                  ),
                                ],
                              );
                            }

                            final docs = snap.data!.docs;
                            return Column(
                              children: [
                                _PrimaryButton(
                                  text: '👥 그룹 관리로 이동',
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupPage()));
                                  },
                                ),
                                const SizedBox(height: 12),
                                ...docs.map((d) {
                                  final m = d.data() as Map<String, dynamic>;
                                  final name = (m['name'] ?? '이름 없는 그룹').toString();
                                  final createdAt = m['createdAt'];
                                  final createdText = (createdAt != null)
                                      ? '생성일 ${(createdAt is Timestamp) ? createdAt.toDate().toString().split(".").first : createdAt.toString()}'
                                      : null;

                                  return _GroupTile(
                                    name: name,
                                    subtitleWidget: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _MemberCountText(groupId: d.id), // ✅ 항상 정확한 구성원 수
                                        if (createdText != null) Text(createdText),
                                      ],
                                    ),
                                    onTap: () {
                                      // ✅ 그룹 상세로 바로 이동 (groupId + groupName 전달)
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => GroupDetailPage(
                                            groupId: d.id,
                                            groupName: name,
                                          ),
                                        ),
                                      ).then((_) => setState(() {})); // ✅ 돌아오면 화면 새로고침
                                    },
                                  );
                                }),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 3) 도움말 카드
                      const _SectionCard(
                        title: '도움말',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GuideRow(icon: Icons.person_add_alt_1, text: '그룹을 만든 뒤 사용자에게 초대를 보내세요.'),
                            SizedBox(height: 8),
                            _GuideRow(icon: Icons.health_and_safety, text: '사용자가 데이터를 저장하면 건강 상태가 그룹에서 확인됩니다.'),
                            SizedBox(height: 8),
                            _GuideRow(icon: Icons.notifications_active_outlined, text: '비정상 심박 등 알림은 수신함에서 확인하세요.'),
                          ],
                        ),
                      ),
                    ],

                    // ===== 사용자 홈 =====
                    if (role == 'user') ...[
                      // 건강 데이터 섹션
                      _SectionCard(
                        title: '건강 데이터',
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(user!.uid)
                              .collection('healthData')
                              .orderBy('timestamp', descending: true)
                              .limit(1)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('아직 건강 데이터가 없습니다.', style: TextStyle(fontSize: 16)),
                                  const SizedBox(height: 12),
                                  _PrimaryButton(
                                    text: '실시간 건강 데이터 저장',
                                    onPressed: () => saveRealHData(
                                      context: context,
                                      getAddressFromCoordinates: getAddressFromCoordinates,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _PrimaryButton(
                                    text: '비정상 건강 데이터 저장 (시연용)',
                                    onPressed: saveAbnormalHData,
                                  ),
                                ],
                              );
                            }

                            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                            final ts = data['timestamp']?.toDate();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: _StatTile(
                                        label: '심박수',
                                        value: '${data['heartRate']} bpm',
                                        icon: Icons.favorite_outline,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _StatTile(
                                        label: '걸음수',
                                        value: '${data['steps']} 보',
                                        icon: Icons.directions_walk_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '📍 ${(data['location'] is Map && data['location'].containsKey('address'))
                                      ? data['location']['address']
                                      : data['location'].toString()}',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                if (ts != null) ...[
                                  const SizedBox(height: 4),
                                  Text('🕒 ${ts.toString()}',
                                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                ],
                                const SizedBox(height: 16),
                                _PrimaryButton(
                                  text: '실시간 건강 데이터 저장',
                                  onPressed: () => saveRealHData(
                                    context: context,
                                    getAddressFromCoordinates: getAddressFromCoordinates,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _PrimaryButton(
                                  text: '비정상 건강 데이터 저장 (시연용)',
                                  onPressed: saveAbnormalHData,
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 그룹 이동
                      _SectionCard(
                        title: '그룹',
                        child: _PrimaryButton(
                          text: '👥 그룹 페이지로 이동',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const GroupPage()),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 초대 목록: 항상 하단
                      // (중략)
// 초대 목록: 초대가 있을 때만 노출
                      if (invites.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: '📨 초대된 그룹 목록',
                          child: Column(
                            children: invites.map((groupId) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.group_outlined),
                                  title: Text('그룹 ID: $groupId'),
                                  trailing: ElevatedButton(
                                    onPressed: () async {
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(user!.uid)
                                          .update({
                                        'groupId': groupId,
                                        'groupInvites': FieldValue.arrayRemove([groupId]),
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('그룹 가입 완료!')),
                                        );
                                        setState(() {}); // 화면 새로고침
                                      }
                                    },
                                    child: const Text('수락'),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===== 재사용 UI 위젯 =====

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final ButtonStyle? style;
  const _PrimaryButton({required this.text, required this.onPressed, this.style});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style ??
          ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
      child: Text(text),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap; // ✅ 탭 가능

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );

    return onTap == null
        ? content
        : InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: content,
    );
  }
}

class _GroupTile extends StatelessWidget {
  final String name;
  final String? subtitle;           // 문자열 서브타이틀
  final Widget? subtitleWidget;     // 위젯 서브타이틀(둘 중 하나 사용)
  final VoidCallback onTap;

  const _GroupTile({
    required this.name,
    this.subtitle,
    this.subtitleWidget,
    required this.onTap,
  }) : assert(subtitle == null || subtitleWidget == null, 'subtitle과 subtitleWidget은 동시에 사용할 수 없습니다.');

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.groups_outlined),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitleWidget ?? (subtitle == null ? null : Text(subtitle!)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _MemberCountText extends StatelessWidget {
  final String groupId;
  const _MemberCountText({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('groupId', isEqualTo: groupId)
          .where('role', isEqualTo: 'user')
          .snapshots(),
      builder: (context, snap) {
        final n = (snap.hasData) ? snap.data!.docs.length : 0;
        return Text('구성원 $n명');
      },
    );
  }
}

class _GuideRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _GuideRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
