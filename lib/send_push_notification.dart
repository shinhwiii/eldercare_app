import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> sendPushNotification({
  required String fcmToken,
  required String title,
  required String body,
  required String guardianId,
  required String senderEmail,
  required String groupName,
}) async {
  // 🔔 푸시 알림 전송용 → Cloud Function에서 이 컬렉션 감지함
  await FirebaseFirestore.instance.collection('notifications').add({
    'fcmToken': fcmToken,
    'title': title,
    'body': body,
    'guardianId': guardianId,
    'senderEmail': senderEmail,
    'groupName': groupName,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // 📥 수신함 표시용 → 알림 수신함에서 읽는 위치
  await FirebaseFirestore.instance
      .collection('users')
      .doc(guardianId)
      .collection('alerts')
      .add({
    'title': title,
    'body': body,
    'senderEmail': senderEmail,
    'groupName': groupName,
    'timestamp': FieldValue.serverTimestamp(),
  });

  print('✅ 알림 Firestore 및 수신함에 저장 완료 (보호자 ID: $guardianId)');
}
