import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';              // ✅ 전화/문자 실행
import 'package:android_intent_plus/android_intent.dart';    // ✅ Android 폴백
import 'dart:io' show Platform;

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
          .where('ownerId', isEqualTo: user!.uid)
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
      'ownerId': user!.uid,
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

  // ✅ 표시용 이름
  String _displayNameFromUserDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;

    final email = (data['email'] as String?)?.trim();
    if (email != null && email.isNotEmpty) {
      final prefix = email.split('@').first;
      if (prefix.isNotEmpty) return prefix;
    }
    return '알 수 없음';
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

  // 📞 그룹 보호자 전화걸기
  Future<void> _callGuardian() async {
    if (currentGroupId == null) return;

    try {
      final groupSnap = await FirebaseFirestore.instance.collection('groups').doc(currentGroupId).get();
      if (!groupSnap.exists) return;

      final guardianId = groupSnap['ownerId'];
      final guardianSnap = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
      if (!guardianSnap.exists) return;

      final phone = (guardianSnap.data()?['phone'] as String?)?.trim();
      if (phone == null || phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('보호자 전화번호가 등록되어 있지 않습니다.')));
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
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('전화 연결 중 오류가 발생했습니다: $e')));
    }
  }

  // 📩 그룹 보호자 문자보내기 (기본 문구 없음)
  Future<void> _smsGuardian() async {
    if (currentGroupId == null) return;

    try {
      final groupSnap = await FirebaseFirestore.instance.collection('groups').doc(currentGroupId).get();
      if (!groupSnap.exists) return;

      final guardianId = groupSnap['ownerId'];
      final guardianSnap = await FirebaseFirestore.instance.collection('users').doc(guardianId).get();
      if (!guardianSnap.exists) return;

      final phone = (guardianSnap.data()?['phone'] as String?)?.trim();
      if (phone == null || phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('보호자 전화번호가 등록되어 있지 않습니다.')));
        return;
      }

      final normalized = _normalizePhone(phone);
      final uri = Uri(scheme: 'sms', path: normalized);

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'android.intent.action.SENDTO',
          data: 'smsto:$normalized',
        );
        await intent.launch();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('문자 연결 중 오류가 발생했습니다: $e')));
    }
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
                const SizedBox(height: 8),

                // ✅ 사용자 입장: 보호자에게 전화/문자 아이콘
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _callGuardian,
                      icon: const Icon(Icons.call, color: Colors.green),
                      iconSize: 28,
                      tooltip: '보호자에게 전화',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _smsGuardian,
                      icon: const Icon(Icons.message, color: Colors.blue),
                      iconSize: 28,
                      tooltip: '보호자에게 문자',
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                const Text('👤 그룹 사용자 목록:', style: TextStyle(fontSize: 16)),
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
                          final uid = userDoc.id;
                          final displayName = _displayNameFromUserDoc(userDoc);

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
                                title: Text(displayName),
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
                  child: const Text(
                    '🚪 그룹 나가기',
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
