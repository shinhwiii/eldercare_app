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

  @override
  void dispose() {
    groupNameController.dispose();
    super.dispose();
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
    ).then((_) => _loadData());
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: role == 'guardian' ? _buildGuardianBody(context) : _buildUserBody(context),
          ),
        ),
      ),
    );
  }

  // ===== Guardian UI =====
  Widget _buildGuardianBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '새 그룹 만들기',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: groupNameController,
                decoration: const InputDecoration(
                  labelText: '그룹 이름',
                  hintText: '예) 우리 가족',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createGroup(),
              ),
              const SizedBox(height: 12),
              _PrimaryButton(text: '➕ 그룹 생성', onPressed: _createGroup),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '내가 만든 그룹',
          child: (myGroups.isEmpty)
              ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('아직 생성한 그룹이 없어요. 위에서 그룹을 만들어 보세요.'),
          )
              : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: myGroups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final g = myGroups[index];
              final name = (g['name'] ?? '이름 없음').toString();
              final ts = (g['createdAt'] is Timestamp) ? (g['createdAt'] as Timestamp).toDate() : null;
              final createdText = ts != null ? '생성일 ${ts.toString().split(".").first}' : '';

              return _GroupTile(
                name: name,
                subtitleWidget: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MemberCountText(groupId: g.id), // ✅ 실시간 구성원 수
                    if (createdText.isNotEmpty) Text(createdText),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupDetailPage(groupId: g.id, groupName: name),
                    ),
                  ).then((_) => _loadData()); // 돌아오면 새로고침
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ===== User UI =====
  Widget _buildUserBody(BuildContext context) {
    if (currentGroupId == null) {
      return const _SectionCard(
        title: '그룹 상태',
        child: Column(
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
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('groups').doc(currentGroupId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _SectionCard(
            title: '그룹 정보',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final groupData = snapshot.data!.data() as Map<String, dynamic>?;
        final groupName = groupData?['name'] ?? '알 수 없음';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionCard(
              title: '가입된 그룹',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('👥 $groupName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _OutlinedIconButton(
                          icon: Icons.call,
                          label: '보호자에게 전화',
                          onPressed: _callGuardian,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _OutlinedIconButton(
                          icon: Icons.message,
                          label: '보호자에게 문자',
                          onPressed: _smsGuardian,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '그룹 사용자',
              child: SizedBox(
                // ListView 높이 계산을 위해 감싸기
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
                    if (users.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('등록된 사용자가 없습니다.'),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
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
                          builder: (context, snap) {
                            String subtitle = '최근 건강 데이터 없음';
                            if (snap.hasData && snap.data!.docs.isNotEmpty) {
                              final data = snap.data!.docs.first.data() as Map<String, dynamic>;
                              final ts = data['timestamp']?.toDate();
                              final hr = data['heartRate'];
                              final steps = data['steps'];
                              subtitle = '💓 ${hr ?? '-'}bpm · 👟 ${steps ?? '-'}보 · 🕒 ${ts?.toString().split(".").first ?? '알 수 없음'}';
                            }
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(subtitle),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _PrimaryButton(
              text: '🚪 그룹 나가기',
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ],
        );
      },
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
        padding: const EdgeInsets.all(20),
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

class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final ButtonStyle? style;
  const _PrimaryButton({required this.text, required this.onPressed, this.style});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style ??
          ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
      child: Text(text),
    );
  }
}

class _OutlinedIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _OutlinedIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        // 가로는 부모(Expanded)가 결정, 높이만 강제
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          // ← 한 줄 고정 + 말줄임
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final Widget? subtitleWidget; // 문자열/위젯 중 하나 사용
  final VoidCallback onTap;
  const _GroupTile({required this.name, this.subtitle, this.subtitleWidget, required this.onTap})
      : assert(subtitle == null || subtitleWidget == null, 'subtitle과 subtitleWidget은 동시에 사용할 수 없습니다.');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: const Icon(Icons.groups_outlined),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitleWidget ?? (subtitle == null ? null : Text(subtitle!)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _MemberCountText extends StatelessWidget {
  final String groupId;
  const _MemberCountText({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('groupId', isEqualTo: groupId)
          .where('role', isEqualTo: 'user')
          .snapshots(),
      builder: (context, snap) {
        final n = (snap.hasData) ? snap.data!.docs.length : 0;
        return Text('구성원 $n명');
      },
    );
  }
}
