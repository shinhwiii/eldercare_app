import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UserHealthSummaryPage extends StatefulWidget {
  final String userId;

  const UserHealthSummaryPage({super.key, required this.userId});

  @override
  State<UserHealthSummaryPage> createState() => _UserHealthSummaryPage();
}

class _UserHealthSummaryPage extends State<UserHealthSummaryPage> {
  String selectedPeriod = '일별';
  List<String> periods = ['일별', '주별', '월별'];
  late Future<List<Map<String, dynamic>>> healthData;

  @override
  void initState() {
    super.initState();
    healthData = fetchGroupedHealthData();
  }

  Future<List<Map<String, dynamic>>> fetchGroupedHealthData() async {
    final now = DateTime.now();
    DateTime startDate;

    if (selectedPeriod == '일별') {
      startDate = now.subtract(const Duration(days: 7));
    } else if (selectedPeriod == '주별') {
      startDate = now.subtract(const Duration(days: 7 * 4));
    } else {
      startDate = now.subtract(const Duration(days: 30 * 6));
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('healthData')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .orderBy('timestamp')
        .get();

    final rawData = snapshot.docs.map((doc) => doc.data()).toList();

    // ✅ 0 데이터 제거
    final validData = rawData.where((item) {
      final hr = (item['heartRate'] ?? 0) as num;
      final steps = (item['steps'] ?? 0) as num;
      return hr > 0 && steps > 0;
    }).toList();

    // 🔄 날짜별 그룹화
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in validData) {
      final date = (item['timestamp'] as Timestamp).toDate();
      final key = DateFormat('yyyy-MM-dd').format(date); // 하루 단위 키
      grouped.putIfAbsent(key, () => []).add(item);
    }

    // 📊 평균 + 누적 계산
    final List<Map<String, dynamic>> groupedData = [];
    for (var entry in grouped.entries) {
      final date = DateFormat('yyyy-MM-dd').parse(entry.key);
      final list = entry.value;

      final avgHeart = list.map((e) => (e['heartRate'] as num)).reduce((a, b) => a + b) / list.length;

      // ✅ 하루 내 기록에서 steps: 마지막 - 처음 값으로 계산
      final sortedByTime = List.from(list)
        ..sort((a, b) =>
            (a['timestamp'] as Timestamp).compareTo(b['timestamp'] as Timestamp));
      final firstSteps = (sortedByTime.first['steps'] ?? 0) as num;
      final lastSteps = (sortedByTime.last['steps'] ?? 0) as num;
      final dailySteps = (lastSteps - firstSteps).clamp(0, double.infinity);

      groupedData.add({
        'timestamp': date,
        'heartRate': avgHeart,
        'steps': dailySteps,
      });
    }

    groupedData.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime)); // 최신순 정렬
    return groupedData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('건강 분석 요약'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          ToggleButtons(
            isSelected: periods.map((p) => p == selectedPeriod).toList(),
            onPressed: (index) {
              setState(() {
                selectedPeriod = periods[index];
                healthData = fetchGroupedHealthData(); // reload
              });
            },
            children: periods.map((label) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(label),
            )).toList(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: healthData,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!;
                if (data.isEmpty) {
                  return const Center(child: Text('해당 기간 동안 데이터가 없습니다.'));
                }

                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final item = data[index];
                    final date = item['timestamp'] as DateTime;
                    final day = DateFormat('yyyy-MM-dd').format(date);
                    final heart = (item['heartRate'] as num).toStringAsFixed(1);
                    final steps = (item['steps'] as num).toInt();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📅 $day', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text('💓 평균 심박수: $heart bpm'),
                            Text('👟 총 걸음수: $steps 보'),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
