import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/image_detection_screen.dart';
import '../screens/live_detection_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/settings_screen.dart';

class AppRoutes {
  static const String main = '/';
  static const String home = '/home';
  static const String live = '/live';
  static const String image = '/image';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
        main: (context) => const MainNavigationScreen(),
        home: (context) => const HomeScreen(),
        live: (context) => const LiveDetectionScreen(),
        image: (context) => const ImageDetectionScreen(),
        settings: (context) => const SettingsScreen(),
      };
}
