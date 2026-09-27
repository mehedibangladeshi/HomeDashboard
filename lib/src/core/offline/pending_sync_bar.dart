import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';

class PendingSyncBar extends ConsumerStatefulWidget {
  const PendingSyncBar({required this.householdId, super.key});
  final String householdId;
  @override
  ConsumerState<PendingSyncBar> createState() => _PendingSyncBarState();
}

class _PendingSyncBarState extends ConsumerState<PendingSyncBar> {
  Timer? _timer;
  List<Map<String, dynamic>> _pending = [];
  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final queue = ref.read(offlineCommandQueueProvider);
      final pending = await queue.pending(widget.householdId);
      if (mounted) setState(() => _pending = pending);
    } catch (_) {/* Sign-out may happen while the local query runs. */}
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    final failed = _pending.where((c) => c['state'] == 'failed').length;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(failed > 0
            ? '$failed saved actions need review'
            : '${_pending.length} saved actions waiting to sync'),
        trailing: TextButton(
            onPressed: () async {
              final queue = ref.read(offlineCommandQueueProvider);
              await queue.retryFailed(widget.householdId);
              await queue.synchronize();
              await _refresh();
            },
            child: const Text('Retry')),
      ),
    );
  }
}
