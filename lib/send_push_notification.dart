import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> sendPushNotification({
  required String fcmToken,
  required String title,
  required String body,
  required String guardianId,
  required String senderEmail,
  required String groupName,
}) async {
  // 1. FCM 전송용 문서 저장
  await FirebaseFirestore.instance.collection('notifications').add({
    'fcmToken': fcmToken,
    'title': title,
    'body': body,
    'guardianId': guardianId,
    'senderEmail': senderEmail,
    'groupName': groupName,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // 2. 보호자 알림 수신함에도 저장
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

  print('✅ FCM 알림 요청 및 보호자 알림 수신함 저장 완료');
}
