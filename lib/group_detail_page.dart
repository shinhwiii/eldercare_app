import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_health_analysis_page.dart';

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

  @override
  void dispose() {
    inviteController.dispose();
    super.dispose();
  }

  // ✅ 표시용 이름 계산: name → email prefix → '알 수 없음'
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

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '알 수 없음';
    final d = ts.toDate();
    return d.toString().split('.').first; // yyyy-mm-dd hh:mm:ss
  }

  Future<void> inviteUserByEmail(String email) async {
    final userQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      if (!mounted) return;
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

  void _openInviteSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('사용자 초대', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: inviteController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '사용자 이메일',
                  hintText: 'example@email.com',
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  final email = inviteController.text.trim();
                  if (email.isEmpty) return;
                  inviteUserByEmail(email);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  final email = inviteController.text.trim();
                  if (email.isEmpty) return;
                  inviteUserByEmail(email);
                  Navigator.pop(ctx);
                },
                child: const Text('초대 보내기'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupUsersStream = FirebaseFirestore.instance
        .collection('users')
        .where('groupId', isEqualTo: widget.groupId)
        .where('role', isEqualTo: 'user')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text('👥 그룹: ${widget.groupName}'),
        actions: [
          IconButton(
            tooltip: '사용자 초대',
            icon: const Icon(Icons.person_add),
            onPressed: _openInviteSheet,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ===== 상단 요약 카드 =====
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.groups)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('그룹', style: Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 4),
                              Text(widget.groupName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              // 구성원 수 실시간
                              StreamBuilder<QuerySnapshot>(
                                stream: groupUsersStream,
                                builder: (context, snap) {
                                  final count = (snap.hasData) ? snap.data!.docs.length : 0;
                                  return Text('구성원 $count명',
                                      style: const TextStyle(color: Colors.grey));
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openInviteSheet,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('초대'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ===== 사용자 리스트 =====
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: groupUsersStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(),
                          ));
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('이 그룹에 참여한 사용자가 없습니다.'),
                          );
                        }

                        final users = snapshot.data!.docs;

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                              builder: (context, healthSnapshot) {
                                // 기본값
                                int? hr;
                                int? steps;
                                String locationText = '위치 정보 없음';
                                Timestamp? ts;

                                if (healthSnapshot.hasData && healthSnapshot.data!.docs.isNotEmpty) {
                                  final data = healthSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                                  hr = data['heartRate'] as int?;
                                  steps = data['steps'] as int?;
                                  final location = data['location'];
                                  locationText = (location is Map && location.containsKey('address'))
                                      ? (location['address']?.toString() ?? '위치 정보 없음')
                                      : (location?.toString() ?? '위치 정보 없음');
                                  ts = data['timestamp'] as Timestamp?;
                                }

                                return _UserCardTile(
                                  name: displayName,
                                  heartRate: hr,
                                  steps: steps,
                                  address: locationText,
                                  updatedAt: _fmtTs(ts),
                                  onOpenAnalysis: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UserHealthAnalysisPage(userId: uid),
                                      ),
                                    );
                                  },
                                  onRemove: () => removeUserFromGroup(uid),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ====== 재사용 타일 위젯 ======
class _UserCardTile extends StatelessWidget {
  final String name;
  final int? heartRate;
  final int? steps;
  final String address;
  final String updatedAt;
  final VoidCallback onOpenAnalysis;
  final VoidCallback onRemove;

  const _UserCardTile({
    required this.name,
    required this.heartRate,
    required this.steps,
    required this.address,
    required this.updatedAt,
    required this.onOpenAnalysis,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이름 + 액션 아이콘 줄
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: '분석 보기',
                      icon: const Icon(Icons.insights_outlined),
                      onPressed: onOpenAnalysis,
                    ),
                    IconButton(
                      tooltip: '강퇴하기',
                      icon: const Icon(Icons.person_remove, color: Colors.red),
                      onPressed: onRemove,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 수치들
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ChipLike(text: '💓 ${heartRate ?? '-'} bpm'),
                    _ChipLike(text: '👟 ${steps ?? '-'} 보'),
                    _ChipLike(text: '🕒 $updatedAt'),
                  ],
                ),
                const SizedBox(height: 6),
                Text('📍 $address', maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipLike extends StatelessWidget {
  final String text;
  const _ChipLike({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
