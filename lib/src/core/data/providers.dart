import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/features/chores/data/chore_repository.dart';
import 'package:home_management/src/features/calendar/data/calendar_repository.dart';
import 'package:home_management/src/features/household/data/household_repository.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:home_management/src/features/spending/data/spending_repository.dart';
import 'package:home_management/src/core/offline/offline_command_queue.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

final householdRepositoryProvider = Provider<HouseholdRepository>(
  (ref) => SupabaseHouseholdRepository(ref.watch(supabaseProvider)),
);

final spendingRepositoryProvider = Provider<SpendingRepository>(
  (ref) => SupabaseSpendingRepository(ref.watch(supabaseProvider)),
);

final choreRepositoryProvider = Provider<ChoreRepository>(
  (ref) => SupabaseChoreRepository(ref.watch(supabaseProvider)),
);

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => SupabaseCalendarRepository(ref.watch(supabaseProvider)),
);

final offlineCommandQueueProvider = Provider<OfflineCommandQueue>(
  (ref) => OfflineCommandQueue(
    ref.watch(spendingRepositoryProvider),
    ref.watch(choreRepositoryProvider),
  ),
);

final currentHouseholdProvider = FutureProvider<Household?>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(householdRepositoryProvider).current();
});
