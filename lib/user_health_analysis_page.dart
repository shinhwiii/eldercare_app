import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ 전화/문자 실행
import 'package:android_intent_plus/android_intent.dart'; // ✅ Android 폴백
import 'dart:io' show Platform;

import 'user_health_summary_page.dart';
import 'user_location_map_page.dart';

class UserHealthAnalysisPage extends StatefulWidget {
  final String userId;

  const UserHealthAnalysisPage({super.key, required this.userId});

  @override
  State<UserHealthAnalysisPage> createState() => _UserHealthAnalysisPageState();
}

class _UserHealthAnalysisPageState extends State<UserHealthAnalysisPage> {
  late Future<List<Map<String, dynamic>>> healthData;

  @override
  void initState() {
    super.initState();
    healthData = fetchHealthData();
  }

  Future<List<Map<String, dynamic>>> fetchHealthData() async {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 30));

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('healthData')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .orderBy('timestamp', descending: true)
        .get();

    final rawData = snapshot.docs.map((doc) => doc.data()).toList();
    final filtered = rawData.where((item) {
      final hr = (item['heartRate'] ?? 0) as num;
      final steps = (item['steps'] ?? 0) as num;
      return hr > 0 && steps > 0;
    }).toList();

    return filtered;
  }

  bool isHeartRateAbnormal(int heartRate) {
    return heartRate <= 50 || heartRate >= 100;
  }

  // ✅ 전화번호 정규화
  String _normalizePhone(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return digitsOnly;
    if (digitsOnly.startsWith('0')) return digitsOnly;
    if (digitsOnly.startsWith('82')) {
      final rest = digitsOnly.substring(2);
      return '0$rest';
    }
    return digitsOnly;
  }

  // ✅ 전화 앱 열기
  Future<void> _callUser() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      final phone = (snap.data()?['phone'] as String?)?.trim();

      if (phone == null || phone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📵 사용자 전화번호가 등록되어 있지 않습니다.')),
        );
        return;
      }

      final normalized = _normalizePhone(phone);
      final uri = Uri(scheme: 'tel', path: normalized);

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'android.intent.action.DIAL',
          data: 'tel:$normalized',
        );
        await intent.launch();
      } else if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('전화 앱을 열 수 없습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전화 연결 중 오류가 발생했습니다: $e')),
      );
    }
  }

  // ✅ 문자 앱 열기
  Future<void> _smsUser() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      final phone = (snap.data()?['phone'] as String?)?.trim();

      if (phone == null || phone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📵 사용자 전화번호가 등록되어 있지 않습니다.')),
        );
        return;
      }

      final normalized = _normalizePhone(phone);
      final uri = Uri(
        scheme: 'sms',
        path: normalized,
        queryParameters: {'body': '건강 상태에 이상이 감지되었습니다. 괜찮으신가요?'},
      );

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'android.intent.action.SENDTO',
          data: 'smsto:$normalized',
          arguments: {'sms_body': '건강 상태에 이상이 감지되었습니다. 괜찮으신가요?'},
        );
        await intent.launch();
      } else if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('문자 앱을 열 수 없습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('문자 연결 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('사용자 건강 분석'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserHealthSummaryPage(userId: widget.userId),
                ),
              );
            },
            child: const Text(
              '건강 분석 요약',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: healthData,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final dataList = snapshot.data!;
          if (dataList.isEmpty) {
            return const Center(child: Text('최근 30일 동안 건강 데이터가 없습니다.'));
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: dataList.length,
                  itemBuilder: (context, index) {
                    final data = dataList[index];
                    final timestamp = (data['timestamp'] as Timestamp).toDate();
                    final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
                    final heartRate = data['heartRate'] as int;

                    return ListTile(
                      title: Text(timeStr),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('💓 $heartRate bpm 👟 ${data['steps']} 보'),
                          Text(
                            '📍 ${(data['location'] is Map && data['location'].containsKey('address'))
                                ? data['location']['address']
                                : data['location'].toString()}',
                          ),
                        ],
                      ),
                      trailing: isHeartRateAbnormal(heartRate)
                          ? const Icon(Icons.warning, color: Colors.red)
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // ✅ 버튼들: 위치 보기 + 전화 걸기 + 문자 보내기
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 위치 버튼 (기존 유지)
                    ElevatedButton.icon(
                      onPressed: () {
                        final latest = dataList.first;
                        final loc = latest['location'];
                        if (loc is Map && loc.containsKey('lat') && loc.containsKey('lng')) {
                          final lat = (loc['lat'] as num).toDouble();
                          final lng = (loc['lng'] as num).toDouble();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserLocationMapPage(lat: lat, lng: lng),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('📍 위치 정보가 없습니다.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.location_on),
                      label: const Text('사용자 실시간 위치 보기'),
                    ),

                    const SizedBox(width: 12),

                    // 전화 버튼 (아이콘만)
                    IconButton(
                      onPressed: _callUser,
                      icon: const Icon(Icons.call, color: Colors.green),
                      iconSize: 32,
                      tooltip: '전화',
                    ),

                    const SizedBox(width: 12),

                    // 문자 버튼 (아이콘만)
                    IconButton(
                      onPressed: _smsUser,
                      icon: const Icon(Icons.message, color: Colors.blue),
                      iconSize: 32,
                      tooltip: '문자',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
