import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final user = FirebaseAuth.instance.currentUser;

  Future<void> saveHealthData() async {
    if (user == null) return;

    final timestamp = DateTime.now().toIso8601String();

    // 예시 더미 데이터
    final int heartRate = 72;
    final int steps = 3450;
    final String location = "37.5665,126.9780"; // 서울 좌표

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('healthData')
        .doc(timestamp)
        .set({
      'heartRate': heartRate,
      'steps': steps,
      'location': location,
      'timestamp': Timestamp.now(),
    });

    // 저장 완료 후 새로고침
    if (mounted) {
      setState(() {});
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 건강 데이터가 저장되었습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: user == null
          ? const Center(child: Text('로그인 정보를 불러올 수 없습니다.'))
          : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('healthData')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('환영합니다, ${user!.email}님!', style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 24),
                  const Text('아직 건강 데이터가 없습니다.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: saveHealthData,
                    child: const Text('건강 데이터 저장하기'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('환영합니다, ${user!.email}님!', style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 24),
                Text('🧡 심박수: ${data['heartRate']} bpm'),
                Text('👟 걸음 수: ${data['steps']} 보'),
                Text('📍 위치: ${data['location']}'),
                Text('🕒 시간: ${data['timestamp'].toDate()}'),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: saveHealthData,
                  child: const Text('건강 데이터 저장하기'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
