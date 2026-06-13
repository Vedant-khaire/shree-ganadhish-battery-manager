import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';
import 'services/notification_service.dart';

void main() async {
  // Disable hash (#) in URLs for modern web path navigation
  usePathUrlStrategy();

  // Ensure Flutter binding is initialized (needed for secure storage on startup)
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Notification Service
  final notificationService = NotificationService.instance;
  await notificationService.initialize();

  // Create Riverpod container and link it to NotificationService
  final container = ProviderContainer();
  notificationService.setContainer(container);
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const App(),
    ),
  );
}
