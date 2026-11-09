import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'transaction_detail_screen.dart';

/// Archived transactions: hidden everywhere else, restorable here.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});
  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final Set<int> _selected = {};
  List<Txn> _visible = const [];

  Future<void> _restore() async {
    final state = context.read<AppState>();
    final n = await state.restore(_selected.toList());
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored $n transaction${n == 1 ? '' : 's'}')));
  }

  void _toggle(Txn t) => setState(() {
        if (!_selected.remove(t.id)) _selected.add(t.id!);
      });

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: selecting ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)) : null,
        title: Text(selecting ? '${_selected.length} selected' : 'Archived'),
        actions: [
          if (selecting) ...[
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: () => setState(() => _selected.addAll(_visible.map((t) => t.id!))),
            ),
            IconButton(tooltip: 'Restore', icon: const Icon(Icons.unarchive_outlined), onPressed: _restore),
          ],
        ],
      ),
      body: Reloader<List<Txn>>(
        load: (repo) => repo.query(const TxnFilter(archived: true)),
        builder: (context, txns) {
          _visible = txns;
          _selected.removeWhere((id) => !txns.any((t) => t.id == id));
          if (txns.isEmpty) {
            return const EmptyState(
              icon: Icons.archive_outlined,
              title: 'Nothing archived',
              message: 'Archived transactions are hidden from lists, totals, reports, the widget and exports.',
            );
          }
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Long-press to select several. Archived SMS are never imported again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ),
            for (final t in txns)
              TxnTile(
                txn: t,
                showDate: true,
                selecting: selecting,
                selected: _selected.contains(t.id),
                onLongPress: () => _toggle(t),
                onTap: selecting
                    ? () => _toggle(t)
                    : () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(id: t.id!))),
              ),
          ]);
        },
      ),
    );
  }
}
