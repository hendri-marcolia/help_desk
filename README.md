# 📱 Help Desk App

A Flutter-based mobile app for managing support tickets, built to connect with a serverless backend on AWS Lambda. Supports secure login, ticket filtering, and push notifications via Firebase Cloud Messaging (FCM).

---

## ✨ Features

- 🔐 Secure login using token authentication  
- 🧾 View and search tickets  
- 🎯 Filter by:
  - Status
  - Category
  - Facility
  - Priority
  - Assigned user
  - Date range
- 🔄 Infinite scroll with pagination  
- 🚨 Push notifications using FCM  
- 📡 Connects to RESTful API backend (AWS Lambda)  
- 📦 Secure token storage  

---

## 📦 Dependencies

- `flutter_secure_storage`  
- `dio`  
- `firebase_core`  
- `firebase_messaging`  

---

## 🚀 Getting Started

### 1. Clone the Repo

```bash
git clone https://github.com/hendri-marcolia/help_desk.git
cd help-desk
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure API Host

Edit `lib/config.dart`:

```dart
const String API_HOST = 'http://<your-api-host>';
```

> 💡 Use your **local IP** (e.g., `192.168.x.x`) if testing locally on a physical device.

### 4. Set Up Firebase

1. Create a Firebase project  
2. Add an Android app and download `google-services.json`  
3. Place `google-services.json` in `android/app/`  
4. Add Firebase SDKs in Gradle and initialize Firebase in code  

More: [Firebase Messaging setup](https://firebase.flutter.dev/docs/messaging/overview)

### 5. Run the App

```bash
flutter run
```

### 6. Build APK

```bash
flutter build apk --release
```

APK will be located at:

```
build/app/outputs/flutter-apk/app-release.apk
```

---

## ⚠️ Known Issues

- If using HTTP (not HTTPS), allow cleartext in `AndroidManifest.xml`:

```xml
<application
  android:usesCleartextTraffic="true"
  ... >
```

- Ensure your backend is accessible to your device via the network.
- FCM notifications might not appear if app is not initialized properly with Firebase.

---

## 📄 License

MIT License
