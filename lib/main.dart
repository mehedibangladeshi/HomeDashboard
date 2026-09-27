import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/app.dart';
import 'package:home_management/src/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:home_management/src/core/notifications/push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
  );
  await PushNotifications.initialize();
  runApp(const ProviderScope(child: HomeManagementApp()));
}
