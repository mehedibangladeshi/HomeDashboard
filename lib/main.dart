import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/app.dart';
import 'package:home_management/src/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:home_management/src/core/notifications/push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = AppConfig.fromEnvironment();
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );
    if (config.pushEnabled) await PushNotifications.initialize();
    runApp(const ProviderScope(child: HomeManagementApp()));
  } catch (_) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.home_outlined, size: 64),
                const SizedBox(height: 16),
                const Text('HomeDashboard could not start.'),
                const Text('Check the app configuration and try again.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: main, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
