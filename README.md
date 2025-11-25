# 📱 Eldercare App

노약자를 위한 건강 모니터링 앱입니다. 사용자는 건강 데이터를 기록하고, 보호자는 그룹을 생성하여 여러 사용자를 관리하고 이상 징후에 대한 푸시 알림을 받을 수 있습니다.

---

## 🛠️ 기능 요약

* 사용자/보호자 역할 구분
* 사용자 건강 데이터 저장 (심박수, 걸음수, 위치)
* 그룹 생성 및 사용자 초대/참여
* 비정상 심박수 감지 시 보호자에게 알림 전송
* 보호자 알림 수신함 확인 가능

---

## 🚀 설치 방법

### 1. 저장소 클론

```bash
git clone https://github.com/shinhwiii/eldercare_app.git
cd eldercare_app
```

### 2. 의존성 설치

```bash
flutter pub get
```

### 3. Firebase 설정 파일 추가

**이 파일들은 Git에 포함되지 않으므로 수동으로 복사해야 합니다.**

* `google-services.json` → `android/app/`
* `GoogleService-Info.plist` → `ios/Runner/`

> 위 파일은 별도 전달받거나 공유된 `.zip` 파일에서 복사하세요.

### 4. 앱 실행

```bash
flutter run
```

---

## ⚙️ Android 설정 참고

* 최소 SDK: 23
* Android NDK: 27.0.12077973
* coreLibraryDesugaring 사용됨

---

## 👨‍👩‍👧‍👦 역할 설명

| 역할            | 설명                         |
| ------------- | -------------------------- |
| 사용자(user)     | 건강 데이터 저장 / 그룹 참여          |
| 보호자(guardian) | 그룹 생성 / 사용자 초대 및 알림 수신함 확인 |

---

## 🔐 Firebase 보안

이 앱은 Firebase 인증, Cloud Firestore, Messaging을 사용합니다.
개발용 API 키는 외부에 노출되지 않도록 주의해 주세요.

* Git에는 Firebase 설정 파일을 절대 올리지 마세요.
* `.gitignore`에 이미 포함되어 있습니다.

---

## ✨ 개발자

* 팀원: 신휘, 이재우
* Flutter version: 3.19.x 이상

---

## 📎 라이센스

본 프로젝트는 학교 실습 목적이며, 상업적 용도로 배포되지 않습니다.
