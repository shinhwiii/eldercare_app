import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_health_analysis_page.dart'; // ✅ 사용자 분석 페이지 import

class AlertInboxPage extends StatelessWidget {
  const AlertInboxPage({super.key});

  Future<void> deleteAllAlerts(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('alerts')
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인 정보를 불러올 수 없습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 알림 수신함'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await deleteAllAlerts(user.uid);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ 모든 알림이 삭제되었습니다.')),
                );
              }
            },
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('alerts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('알림이 없습니다.'));
          }

          final alerts = snapshot.data!.docs;

          return ListView.builder(
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index].data() as Map<String, dynamic>;
              final title = alert['title'] ?? '제목 없음';
              final body = alert['body'] ?? '내용 없음';
              final senderName = alert['senderName']; // ✅ 이름 필드
              final senderEmail = alert['senderEmail'];
              final senderDisplay =
              (senderName != null && senderName.toString().trim().isNotEmpty)
                  ? senderName
                  : (senderEmail ?? '알 수 없음');

              final timestamp = alert['timestamp']?.toDate();
              final abnormalUserId = alert['userId']; // ✅ 알림 속 사용자 ID 가져오기

              return ListTile(
                leading: const Icon(Icons.notifications),
                title: Text(title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(body),
                    Text('보낸 사람: $senderDisplay'), // ✅ 이름 우선 표시
                    if (timestamp != null)
                      Text('🕒 ${timestamp.toString()}',
                          style: const TextStyle(fontSize: 12)),
                  ],
                ),
                onTap: abnormalUserId != null
                    ? () {
                  print('✅ 알림 클릭됨, userId: $abnormalUserId');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          UserHealthAnalysisPage(userId: abnormalUserId),
                    ),
                  );
                }
                    : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('❗ 이 알림에는 사용자 ID 정보가 없습니다.')),
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
