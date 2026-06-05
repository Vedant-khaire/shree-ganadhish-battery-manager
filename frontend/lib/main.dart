import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';

void main() {
  // Disable hash (#) in URLs for modern web path navigation
  usePathUrlStrategy();

  // Ensure Flutter binding is initialized (needed for secure storage on startup)
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
