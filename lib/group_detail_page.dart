import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupDetailPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController inviteController = TextEditingController();

  Future<void> inviteUserByEmail(String email) async {
    final userQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('해당 이메일의 사용자를 찾을 수 없습니다.')),
      );
      return;
    }

    final userDoc = userQuery.docs.first;

    await FirebaseFirestore.instance.collection('users').doc(userDoc.id).update({
      'groupInvites': FieldValue.arrayUnion([widget.groupId]),
    });

    if (!mounted) return;
    inviteController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대가 성공적으로 전송되었습니다.')),
    );
  }

  Future<void> removeUserFromGroup(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'groupId': FieldValue.delete(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('사용자를 그룹에서 추방했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('👥 그룹: ${widget.groupName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('사용자 초대'),
                  content: TextField(
                    controller: inviteController,
                    decoration: const InputDecoration(labelText: '사용자 이메일 입력'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        inviteUserByEmail(inviteController.text.trim());
                        Navigator.pop(context);
                      },
                      child: const Text('초대'),
                    ),
                  ],
                ),
              );
            },
          )
        ],
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .where('groupId', isEqualTo: widget.groupId)
            .where('role', isEqualTo: 'user')
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;

          if (users.isEmpty) {
            return const Center(child: Text('이 그룹에 참여한 사용자가 없습니다.'));
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userDoc = users[index];
              final uid = userDoc.id;
              final email = userDoc['email'];

              return FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('healthData')
                    .orderBy('timestamp', descending: true)
                    .limit(1)
                    .get(),
                builder: (context, healthSnapshot) {
                  String subtitle = '건강 데이터 없음';
                  if (healthSnapshot.hasData && healthSnapshot.data!.docs.isNotEmpty) {
                    final data = healthSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                    final timestamp = data['timestamp'];
                    final timeStr = timestamp != null ? timestamp.toDate().toString() : '알 수 없음';
                    subtitle =
                    '💓 ${data['heartRate']}bpm, 👟 ${data['steps']}보, 📍 ${data['location']}, 🕒 최근 갱신: $timeStr';
                  }

                  return ListTile(
                    title: Text(email),
                    subtitle: Text(subtitle),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_remove, color: Colors.red),
                      onPressed: () => removeUserFromGroup(uid),
                      tooltip: '강퇴하기',
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}