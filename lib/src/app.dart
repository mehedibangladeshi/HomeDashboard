import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/theme/app_theme.dart';
import 'package:home_management/src/features/auth/presentation/sign_in_screen.dart';
import 'package:home_management/src/features/household/presentation/onboarding_screen.dart';
import 'package:home_management/src/features/shell/presentation/home_shell.dart';
import 'package:home_management/src/core/notifications/push_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:home_management/src/features/spending/presentation/spending_screen.dart';
import 'package:home_management/src/features/chores/presentation/chores_screen.dart';
import 'package:home_management/src/features/calendar/presentation/calendar_screen.dart';
import 'package:home_management/src/features/dashboard/presentation/today_screen.dart';

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

class _SessionGate extends ConsumerStatefulWidget {
  const _SessionGate();

  @override
  ConsumerState<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<_SessionGate>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _synchronize());
    WidgetsBinding.instance.addPostFrameCallback((_) => _synchronize());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _synchronize();
  }

  Future<void> _synchronize() async {
    if (!mounted) return;
    try {
      final completed =
          await ref.read(offlineCommandQueueProvider).synchronize();
      if (mounted && completed > 0) {
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(choreOccurrencesProvider);
        ref.invalidate(householdEventsProvider);
        ref.invalidate(dashboardProvider);
      }
    } catch (_) {
      // Durable pending commands remain available for the next reconnect.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectivityProvider, (_, next) {
      next.whenData((values) {
        if (values.any((value) => value != ConnectivityResult.none)) {
          _synchronize();
        }
      });
    });
    ref.watch(authStateProvider);
    ref.listen(authStateProvider, (_, __) => _synchronize());
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
