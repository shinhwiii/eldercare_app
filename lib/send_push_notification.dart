import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> sendPushNotification({
  required String fcmToken,
  required String title,
  required String body,
  required String guardianId,
  required String senderEmail,     // ✅ 기존 호환 유지
  String? senderName,              // ✅ 새로 추가: 이름 우선 사용
  required String groupName,
  required String abnormalUserId,  // 비정상 사용자 ID
}) async {
  // ✅ 표시용 발신자: senderName → (없으면) senderEmail 앞부분 → '회원'
  String displaySender;
  if (senderName != null && senderName.trim().isNotEmpty) {
    displaySender = senderName.trim();
  } else if (senderEmail.trim().isNotEmpty) {
    displaySender = senderEmail.split('@').first;
  } else {
    displaySender = '회원';
  }

  // 🔔 Cloud Function 트리거용 컬렉션
  await FirebaseFirestore.instance.collection('notifications').add({
    'fcmToken': fcmToken,
    'title': title,
    'body': body,
    'guardianId': guardianId,
    'groupName': groupName,
    'timestamp': FieldValue.serverTimestamp(),
    'userId': abnormalUserId,

    // ✅ 표시 관련 필드
    'senderName': displaySender,     // ← 알림에 보여줄 이름
    'senderEmail': senderEmail,      // ← 호환용(기존 로직 사용 시)
  });

  // 📥 보호자 수신함(앱에서 보여줄 데이터)
  await FirebaseFirestore.instance
      .collection('users')
      .doc(guardianId)
      .collection('alerts')
      .add({
    'title': title,
    'body': body,
    'groupName': groupName,
    'timestamp': FieldValue.serverTimestamp(),
    'userId': abnormalUserId,

    // ✅ 표시 관련 필드
    'senderName': displaySender,     // ← 여기만 읽어도 이름으로 표시 가능
    'senderEmail': senderEmail,      // ← 필요 시 레거시 표시에 사용
  });

  print('✅ 알림 저장 완료 (보호자 ID: $guardianId, 보낸이: $displaySender)');
}
