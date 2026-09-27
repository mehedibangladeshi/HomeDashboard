import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'outbox_store.dart';

Future<OutboxStore> openStore() async {
  final db = await openDatabase(
    path.join(await getDatabasesPath(), 'home_dashboard_outbox.db'),
    version: 1,
    onCreate: (db, _) => db.execute(
        'CREATE TABLE commands (id TEXT PRIMARY KEY, payload TEXT NOT NULL)'),
  );
  return _SqliteOutbox(db);
}

class _SqliteOutbox implements OutboxStore {
  _SqliteOutbox(this.db);
  final Database db;
  Map<String, dynamic> decode(Map<String, Object?> row) =>
      jsonDecode(row['payload'] as String) as Map<String, dynamic>;
  Map<String, Object?> encode(Map<String, dynamic> command) =>
      {'id': command['id'], 'payload': jsonEncode(command)};

  @override
  Future<void> insert(Map<String, dynamic> command) async {
    await db.insert('commands', encode(command));
  }

  @override
  Future<void> update(Map<String, dynamic> command) async {
    await db.update('commands', encode(command),
        where: 'id = ?', whereArgs: [command['id']]);
  }

  @override
  Future<void> remove(String id) async {
    await db.delete('commands', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String scope) async =>
      (await db.query('commands'))
          .map(decode)
          .where((c) => c['scope'] == scope)
          .toList();

  @override
  Future<List<Map<String, dynamic>>> claim(String scope, DateTime now) =>
      db.transaction((txn) async {
        final commands = (await txn.query('commands'))
            .map(decode)
            .where((c) => isReady(c, scope, now))
            .take(20)
            .map((c) => lease(c, now))
            .toList();
        for (final command in commands) {
          await txn.update('commands', encode(command),
              where: 'id = ?', whereArgs: [command['id']]);
        }
        return commands;
      });
}
