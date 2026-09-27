import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class PushNotifications {
  static bool _available = false;
  static String? _registeredUserId;

  static Future<void> initialize() async {
    try {
      if (kIsWeb) {
        const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
        const appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
        const messagingSenderId = String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
        );
        const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
        if ([
          apiKey,
          appId,
          messagingSenderId,
          projectId,
        ].any((value) => value.isEmpty)) {
          return;
        }
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  static Future<void> registerCurrentDevice(SupabaseClient supabase) async {
    if (!_available || supabase.auth.currentUser == null) return;
    if (_registeredUserId == supabase.auth.currentUser!.id) return;
    _registeredUserId = supabase.auth.currentUser!.id;
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await messaging.getToken(
      vapidKey: kIsWeb
          ? const String.fromEnvironment('FIREBASE_WEB_VAPID_KEY')
          : null,
    );
    if (token != null) await _save(supabase, token);
    messaging.onTokenRefresh.listen((value) => _save(supabase, value));
  }

  static Future<void> _save(SupabaseClient supabase, String token) async {
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
    await supabase.from('device_tokens').upsert({
      'user_id': supabase.auth.currentUser!.id,
      'token': token,
      'platform': platform,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }
}
