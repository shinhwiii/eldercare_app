import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'group_detail_page.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final user = FirebaseAuth.instance.currentUser;
  final TextEditingController groupNameController = TextEditingController();
  String role = '';
  String? currentGroupId;
  List<QueryDocumentSnapshot> myGroups = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
    final userRole = doc.data()?['role'] ?? 'user';
    currentGroupId = doc.data()?['groupId'];

    if (userRole == 'guardian') {
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('createdBy', isEqualTo: user!.uid)
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        role = 'guardian';
        myGroups = groupSnapshot.docs;
      });
    } else {
      setState(() {
        role = 'user';
      });
    }
  }

  Future<void> _createGroup() async {
    final groupName = groupNameController.text.trim();
    if (groupName.isEmpty) return;

    final newGroupRef = await FirebaseFirestore.instance.collection('groups').add({
      'name': groupName,
      'createdBy': user!.uid,
      'createdAt': Timestamp.now(),
    });

    groupNameController.clear();
    await _loadData();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailPage(groupId: newGroupRef.id, groupName: groupName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (role.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('그룹 페이지')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: role == 'guardian'
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📌 그룹 생성', style: TextStyle(fontSize: 16)),
            TextField(
              controller: groupNameController,
              decoration: const InputDecoration(labelText: '새 그룹 이름'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _createGroup,
              child: const Text('➕ 그룹 생성'),
            ),
            const Divider(height: 32),
            const Text('📂 내가 만든 그룹 목록', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: myGroups.length,
                itemBuilder: (context, index) {
                  final group = myGroups[index];
                  final name = group['name'] ?? '이름 없음';
                  final time = group['createdAt'] as Timestamp;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(time.toDate().toString()),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailPage(
                            groupId: group.id,
                            groupName: name,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        )
            : currentGroupId == null
            ? const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_off, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                '👤 아직 그룹에 가입하지 않았어요.\n초대를 수락하거나 관리자에게 문의해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        )
            : FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('groups').doc(currentGroupId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final groupData = snapshot.data!.data() as Map<String, dynamic>?;
            final groupName = groupData?['name'] ?? '알 수 없음';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                Text('👥 가입된 그룹: $groupName', style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 16),
                const Text('📧 그룹 사용자 목록:', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('groupId', isEqualTo: currentGroupId)
                        .where('role', isEqualTo: 'user')
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final users = userSnapshot.data!.docs;

                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final userDoc = users[index];
                          final email = userDoc['email'];
                          final uid = userDoc.id;

                          return FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('healthData')
                                .orderBy('timestamp', descending: true)
                                .limit(1)
                                .get(),
                            builder: (context, snapshot) {
                              String subtitle = '최근 건강 데이터 없음';
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                                final timestamp = data['timestamp']?.toDate();
                                subtitle = '최근 갱신: ${timestamp ?? '알 수 없음'}';
                              }
                              return ListTile(
                                leading: const Icon(Icons.person),
                                title: Text(email),
                                subtitle: Text(subtitle),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
                      'groupId': FieldValue.delete(),
                    });

                    if (!mounted) return;
                    setState(() {
                      currentGroupId = null;
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('그룹에서 성공적으로 나갔습니다.')),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('🚪 그룹 나가기',
                  style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}