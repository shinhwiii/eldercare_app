# 📱 Eldercare App

노년층의 안전을 위해 **건강 데이터·위치·낙상 여부를 실시간 모니터링**하고, 보호자가 여러 사용자를 그룹으로 관리할 수 있는 Flutter 기반 헬스케어 앱입니다.
심박수·걸음수·위치·낙상 데이터를 기반으로 이상 징후를 탐지하여 보호자에게 즉시 알림을 전송합니다.

---

## 🧩 프로젝트 목적

고령화 사회에서 **독거 노인의 돌봄 사각지대 해소**를 위해
스마트워치·센서·스마트폰을 활용한 **비대면 건강 모니터링 시스템**을 구현하였습니다.

---

## 🛠️ 주요 기능

### 👤 역할 기반 기능

| 역할                | 기능                                                     |
| ----------------- | ------------------------------------------------------ |
| **사용자(User)**     | **건강 데이터 저장(심박수·걸음수)**, 위치 기록, **낙상 감지**, 그룹 참여            |
| **보호자(Guardian)** | 그룹 생성·관리, 사용자 초대/수락, 사용자 건강 데이터·그래프 조회, **이상 징후·낙상 알림 수신** |

---

### 📊 핵심 기능 상세

#### 🩺 **1. 건강 데이터 수집 및 저장**

* 심박수(Heart Rate)
* 걸음수(Step Count)
* Firestore에 사용자별로 자동 누적 저장

#### 👣 **2. 위치 추적 (GPS 기반)**

* 실시간 위치 업데이트
* 보호자는 지도(Map)에서 사용자 위치 조회 가능

#### 🧎 **3. 낙상 감지 (Fall Detection)**

* 스마트폰 가속도 센서 기반
* 급격한 가속 변화 → 낙상 판단
* 즉시 보호자에게 FCM 푸시 알림 전송

#### 👥 **4. 그룹 관리 시스템**

* 보호자: 그룹 생성 가능
* 사용자: 보호자의 초대 수락 후 그룹 참여
* 한 보호자는 여러 사용자 관리 가능
* 사용자별 건강 분석 페이지 제공

#### 🔔 **5. 알림 시스템**

* 심박수 이상 감지 → 보호자에게 자동 알림
* 낙상 감지 → 즉시 알림
* 보호자는 알림 수신함(Inbox)에서 기록 확인

#### ⚙️ **6. 백그라운드 서비스**

* 앱이 종료되어도 스마트 워치를 통해 건강 데이터와 이상 징후 계속 모니터링
* Background Service + Awesome Notifications 사용

---

## 🧱 기술 스택

### **Frontend**

* Flutter 3.19.x+
* Dart
* Google Maps Flutter
* Awesome Notifications

### **Backend**

* Firebase Authentication
* Cloud Firestore
* Firebase Cloud Messaging (FCM)

### **센서/디바이스**

* 가속도 센서 기반 낙상 감지 (fall_detector.dart)
* geolocator/geocoding (GPS)
* health API / Health Connect 기반 구조

---

## 🚀 설치 및 실행 방법

### 1) 저장소 클론

```bash
git clone https://github.com/shinhwiii/eldercare_app.git
cd eldercare_app
```

### 2) 의존성 설치

```bash
flutter pub get
```

### 3) Firebase 설정 파일 추가

이 파일들은 Git에 포함되지 않습니다.

```
android/app/google-services.json  
ios/Runner/GoogleService-Info.plist
```

> 관리자에게 문의해주세요.

### 4) 앱 실행

```bash
flutter run
```

---

## 📂 프로젝트 구조 요약

```
lib/
 ├─ main.dart
 ├─ home_screen.dart
 ├─ login/
 │    ├─ login_screen.dart
 │    └─ sign_up_screen.dart
 ├─ group/
 │    ├─ group_page.dart
 │    ├─ group_detail_page.dart
 │    ├─ group_invite_page.dart
 │    └─ group_create_page.dart
 ├─ health/
 │    ├─ user_health_summary_page.dart
 │    ├─ user_health_analysis_page.dart
 │    ├─ health_graph_widget.dart
 │    └─ save_health_data.dart
 ├─ location/
 │    ├─ user_location_map_page.dart
 │    └─ location_service.dart
 ├─ notifications/
 │    ├─ send_push_notification.dart
 │    └─ notification_service.dart
 ├─ background/
 │    ├─ background_task.dart
 │    └─ background_handler.dart
 ├─ sensors/
 │    └─ fall_detector.dart
 └─ firebase_options.dart
```

---

## 🧪 사용자/보호자 플로우

### 사용자(User)

1. 로그인
2. 그룹 초대 수락
3. 심박수/걸음수 자동 기록
4. GPS 위치 업데이트
5. 낙상 시 자동 감지 → 알림 전송

### 보호자(Guardian)

1. 그룹 생성
2. 사용자 초대
3. 낙상·심박수 이상 알림 수신
4. 건강 그래프 분석
5. 사용자 실시간 위치 확인

---

## 📈 향후 확장 계획

* AI 기반 건강 이상 예측 모델 적용
* Wear OS / Galaxy Watch / Apple Watch 연동
* 의료기관 연동
* 응급 신고 자동화 기능

---

## ✨ 개발자

* 팀원: **신휘**, **이재우**
* Dankook University – Capstone Design

---

## 📎 라이선스

본 프로젝트는 교육·연구 목적이며 상업적으로 배포되지 않습니다.

---

필요하면 README에 **앱 스크린샷 섹션**, **아키텍처 다이어그램**, **배지(Badge)**, **GIF 데모**, **캡스톤 발표용 문서 버전**까지 추가해줄 수 있어.
