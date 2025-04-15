import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'group_page.dart';

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

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('healthData')
        .doc(timestamp)
        .set({
      'heartRate': 72,
      'steps': 3450,
      'location': '37.5665,126.9780',
      'timestamp': Timestamp.now(),
    });

    if (mounted) {
      setState(() {});
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 건강 데이터가 저장되었습니다.')),
    );
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

          if (role == 'guardian') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('안녕하세요, ${user!.email}님 (보호자)', style: const TextStyle(fontSize: 18)),
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
            );
          }

          // 사용자 화면
          return Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('환영합니다, ${user!.email}님!', style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),

                  // 건강 데이터
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user!.uid)
                        .collection('healthData')
                        .orderBy('timestamp', descending: true)
                        .limit(1)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Column(
                          children: [
                            const Text('아직 건강 데이터가 없습니다.'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: saveHealthData,
                              child: const Text('건강 데이터 저장하기'),
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
                          Text('📍 위치: ${data['location']}'),
                          Text('🕒 시간: ${data['timestamp'].toDate()}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: saveHealthData,
                            child: const Text('건강 데이터 저장하기'),
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

                  const SizedBox(height: 24),

                  // 초대된 그룹
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(user!.uid).get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();

                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      final List<dynamic> invites = data['groupInvites'] ?? [];

                      if (invites.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Divider(height: 32),
                          const Text('📩 초대된 그룹', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          ...invites.map((groupId) {
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance.collection('groups').doc(groupId).get(),
                              builder: (context, groupSnapshot) {
                                if (!groupSnapshot.hasData) return const Text('불러오는 중...');
                                final groupData = groupSnapshot.data!.data() as Map<String, dynamic>?;
                                final name = groupData?['name'] ?? '알 수 없는 그룹';

                                return ListTile(
                                  title: Text(name),
                                  subtitle: Text('그룹 ID: $groupId'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
                                            'groupId': groupId,
                                            'groupInvites': FieldValue.arrayRemove([groupId])
                                          });
                                          if (context.mounted) setState(() {});
                                        },
                                        child: const Text('수락'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey[300],
                                          foregroundColor: Colors.black,
                                        ),
                                        onPressed: () async {
                                          await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
                                            'groupInvites': FieldValue.arrayRemove([groupId])
                                          });
                                          if (context.mounted) setState(() {});
                                        },
                                        child: const Text('거절'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ],
                      );
                    },
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
