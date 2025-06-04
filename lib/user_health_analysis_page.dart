import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final latest = dataList.first;
                    final loc = latest['location'];
                    if (loc is Map && loc.containsKey('lat') && loc.containsKey('lng')) {
                      final lat = loc['lat'] as double;
                      final lng = loc['lng'] as double;
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
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
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
