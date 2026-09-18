# BIRU Go

Offline, on-device bird image recognition mobile app built with Flutter and TensorFlow Lite.

## Features

- **Offline Inference**: Runs 100% on-device without internet or cloud APIs.
- **Live Camera Detection**: Real-time detection using YOLO11n (320x320).
- **Photo & Gallery Detection**: High-resolution image analysis using YOLOv8n (640x640).
- **Local History**: Saves detection results locally using SQLite.

## Models

- **Live Camera**: YOLO11n (320×320) — `assets/models/yolo11n.tflite`
- **Photo / Gallery**: YOLOv8n (640×640) — `assets/models/yolov8n.tflite`
- **Dataset**: NABirds Dataset (555 bird species)

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.24.0 or newer)
- [Dart SDK](https://dart.dev/get-dart) (v3.5.0 or newer)
- [Android Studio](https://developer.android.com/studio) / Android SDK (minSdk 24)
- Physical Android device or Android Emulator

### Installation & Setup

```bash
# 1. Clone repository
git clone https://github.com/dsisme-1/BIRU-Go.git
cd BIRU-Go

# 2. Install dependencies
flutter pub get

# 3. Run application
flutter run
```

### Building Release APK

```bash
flutter build apk --release
```

The APK will be generated at:  
`build/app/outputs/flutter-apk/app-release.apk`

## Project Structure

```text
biru/
├── android/          # Native Android configuration
├── assets/
│   ├── images/       # App logo & icons
│   ├── labels/       # classes.txt (555 species)
│   └── models/       # TFLite models (YOLO11n & YOLOv8n)
├── lib/
│   ├── app/          # App setup & routes
│   ├── inference/    # Preprocessing, postprocessing & NMS
│   ├── models/       # Data classes
│   ├── screens/      # UI screens (Home, Live, Image, Result, Settings)
│   ├── services/     # Camera & TFLite Detector
│   ├── utils/        # Image & coordinate utils
│   ├── widgets/      # UI components & overlay
│   └── main.dart     # Entry point
└── pubspec.yaml      # Dependencies
```

## Privacy & Permissions

- **Camera**: Used only for live preview and photo capture.
- **Storage / Photos**: Used only when selecting bird images from the gallery.
- **Internet**: No internet permission requested.

## Developer & Credits

- **Developer**: David Suharjanto
- **Dataset**: NABirds (North American Birds) Dataset
- **Runtime**: TensorFlow Lite (`tflite_flutter`)
