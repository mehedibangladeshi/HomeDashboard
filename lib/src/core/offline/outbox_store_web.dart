import 'package:idb_shim/idb_browser.dart';
import 'outbox_store.dart';

Future<OutboxStore> openStore() async {
  final db = await idbFactoryBrowser.open(
    'home_dashboard_outbox',
    version: 1,
    onUpgradeNeeded: (event) =>
        event.database.createObjectStore('commands', keyPath: 'id'),
  );
  return _IndexedDbOutbox(db);
}

class _IndexedDbOutbox implements OutboxStore {
  _IndexedDbOutbox(this.db);
  final Database db;
  @override
  Future<void> insert(Map<String, dynamic> command) async {
    final txn = db.transaction('commands', idbModeReadWrite);
    await txn.objectStore('commands').add(command);
    await txn.completed;
  }

  @override
  Future<void> update(Map<String, dynamic> command) async {
    final txn = db.transaction('commands', idbModeReadWrite);
    await txn.objectStore('commands').put(command);
    await txn.completed;
  }

  @override
  Future<void> remove(String id) async {
    final txn = db.transaction('commands', idbModeReadWrite);
    await txn.objectStore('commands').delete(id);
    await txn.completed;
  }

  @override
  Future<List<Map<String, dynamic>>> list(String scope) async {
    final txn = db.transaction('commands', idbModeReadOnly);
    final rows = await txn.objectStore('commands').getAll();
    await txn.completed;
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((c) => c['scope'] == scope)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> claim(String scope, DateTime now) async {
    final txn = db.transaction('commands', idbModeReadWrite);
    final store = txn.objectStore('commands');
    final rows = await store.getAll();
    final commands = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((c) => isReady(c, scope, now))
        .take(20)
        .map((c) => lease(c, now))
        .toList();
    for (final command in commands) {
      await store.put(command);
    }
    await txn.completed;
    return commands;
  }
}
