import 'outbox_store.dart';

Future<OutboxStore> openStore() =>
    throw UnsupportedError('No durable local store on this platform.');
