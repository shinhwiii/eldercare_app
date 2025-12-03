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
  final bool readOnly; // ✅ 추가: 사용자 모드에서 버튼 숨김

  const UserHealthAnalysisPage({
    super.key,
    required this.userId,
    this.readOnly = false, // 기본은 보호자 모드
  });

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

  bool isHeartRateAbnormal(int heartRate) => heartRate <= 50 || heartRate >= 100;

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

  String _fmtTs(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return DateFormat('yyyy-MM-dd HH:mm').format(d);
    }
    if (ts is DateTime) return DateFormat('yyyy-MM-dd HH:mm').format(ts);
    return '알 수 없음';
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
            child: const Text('건강 분석 요약'),
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

          // 최신 데이터(헤더 카드 요약용)
          final latest = dataList.first;
          final latestHr = latest['heartRate'] as int;
          final latestSteps = latest['steps'] as int;
          final latestAddr = (latest['location'] is Map && latest['location'].containsKey('address'))
              ? latest['location']['address'].toString()
              : latest['location'].toString();
          final latestWhen = _fmtTs(latest['timestamp']);

          return Column(
            children: [
              // ===== 상단 요약 카드 =====
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SectionCard(
                  title: '사용자 최근 상태',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatPill(
                              icon: Icons.favorite_outline,
                              label: '심박수',
                              value: '$latestHr bpm',
                              danger: isHeartRateAbnormal(latestHr),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatPill(
                              icon: Icons.directions_walk_outlined,
                              label: '걸음수',
                              value: '$latestSteps 보',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('📍 $latestAddr', maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('🕒 $latestWhen', style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),

                      // ===== 액션 버튼: readOnly=false 일 때만 노출 =====
                      if (!widget.readOnly)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
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
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Icon(Icons.location_on_outlined),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _callUser,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Icon(Icons.call, color: Colors.green),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _smsUser,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Icon(Icons.message, color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // ===== 리스트 =====
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: dataList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = dataList[index];
                    final timeStr = _fmtTs(data['timestamp']);
                    final heartRate = data['heartRate'] as int;
                    final steps = data['steps'] as int;
                    final address = (data['location'] is Map && data['location'].containsKey('address'))
                        ? data['location']['address'].toString()
                        : data['location'].toString();

                    final abnormal = isHeartRateAbnormal(heartRate);

                    return Container(
                      decoration: BoxDecoration(
                        color: abnormal ? Colors.red.withOpacity(0.03) : Colors.white,
                        border: Border.all(color: abnormal ? Colors.red.shade200 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  timeStr,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                              ),
                              if (abnormal)
                                const _Badge(text: '이상 징후', icon: Icons.warning_amber_rounded),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _SmallStat(
                                  icon: Icons.favorite_outline,
                                  label: '심박수',
                                  value: '$heartRate bpm',
                                  danger: abnormal,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SmallStat(
                                  icon: Icons.directions_walk_outlined,
                                  label: '걸음수',
                                  value: '$steps 보',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('📍 $address', maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ===== 재사용 위젯 =====

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool danger;
  const _StatPill({required this.icon, required this.label, required this.value, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final borderColor = danger ? Colors.red.shade300 : Colors.grey.shade300;
    final bg = danger ? Colors.red.withOpacity(0.04) : Colors.grey[50];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? Colors.red : null),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: danger ? Colors.red : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool danger;
  const _SmallStat({required this.icon, required this.label, required this.value, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? Colors.red.withOpacity(0.04) : Colors.grey[50],
        border: Border.all(color: danger ? Colors.red.shade200 : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label  •  $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Badge({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.red),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
