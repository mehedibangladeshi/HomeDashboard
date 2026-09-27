import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/theme/app_theme.dart';
import 'package:home_management/src/features/auth/presentation/sign_in_screen.dart';
import 'package:home_management/src/features/household/presentation/onboarding_screen.dart';
import 'package:home_management/src/features/shell/presentation/home_shell.dart';
import 'package:home_management/src/core/notifications/push_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HomeManagementApp extends ConsumerWidget {
  const HomeManagementApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'Home Management',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _SessionGate(),
      );
}

class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(connectivityProvider, (_, next) {
      next.whenData((values) {
        if (values.any((value) => value != ConnectivityResult.none)) {
          ref.read(offlineCommandQueueProvider).synchronize();
        }
      });
    });
    ref.watch(authStateProvider);
    final client = ref.watch(supabaseProvider);
    if (client.auth.currentSession == null) return const SignInScreen();
    PushNotifications.registerCurrentDevice(client);
    return ref.watch(currentHouseholdProvider).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            body: Center(child: Text('Could not load your household: $error')),
          ),
          data: (household) => household == null
              ? const OnboardingScreen()
              : HomeShell(household: household),
        );
  }
}
