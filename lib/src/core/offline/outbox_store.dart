import 'outbox_store_stub.dart'
    if (dart.library.io) 'outbox_store_io.dart'
    if (dart.library.js_interop) 'outbox_store_web.dart' as platform;

abstract interface class OutboxStore {
  Future<void> insert(Map<String, dynamic> command);
  Future<List<Map<String, dynamic>>> claim(String scope, DateTime now);
  Future<void> remove(String id);
  Future<void> update(Map<String, dynamic> command);
  Future<List<Map<String, dynamic>>> list(String scope);
}

Future<OutboxStore> openOutboxStore() => platform.openStore();

bool isReady(Map<String, dynamic> command, String scope, DateTime now) =>
    command['scope'] == scope &&
    command['state'] != 'failed' &&
    DateTime.parse(command['retryAt'] as String).isBefore(now) &&
    (command['leaseUntil'] == null ||
        DateTime.parse(command['leaseUntil'] as String).isBefore(now));

Map<String, dynamic> lease(Map<String, dynamic> command, DateTime now) => {
      ...command,
      'state': 'syncing',
      'leaseUntil':
          now.add(const Duration(minutes: 2)).toUtc().toIso8601String(),
    };
