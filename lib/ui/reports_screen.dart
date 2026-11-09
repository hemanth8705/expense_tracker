import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'export_sheet.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _period = Period.thisMonth(DateTime.now());
  TxnType _type = TxnType.debit;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final base = TxnFilter(start: _period.start, end: _period.end);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export CSV / Excel',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => showExportSheet(context, _period),
          ),
        ],
      ),
      body: Reloader<(Totals, List<TagTotal>)>(
        deps: (_period, _type),
        load: (repo) async => (
          await repo.totals(base),
          await repo.totalsByTag(base.copyWith(type: _type)),
        ),
        builder: (context, data) {
          final (totals, byTag) = data;
          final dirTotal = _type == TxnType.debit ? totals.debit : totals.credit;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _period.isMonth ? () => setState(() => _period = _period.shiftMonth(-1)) : null,
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final p = await pickPeriod(context);
                      if (p != null) setState(() => _period = p);
                    },
                    child: Text(_period.label,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _period.isMonth ? () => setState(() => _period = _period.shiftMonth(1)) : null,
                ),
              ]),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TotalsCard(totals)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<TxnType>(
                segments: const [
                  ButtonSegment(value: TxnType.debit, label: Text('Spent (debits)')),
                  ButtonSegment(value: TxnType.credit, label: Text('Received (credits)')),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            ),
            SectionTitle('By tag · ${money(dirTotal)}'),
            if (byTag.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Nothing in this period.',
                    textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final row in byTag) _tagRow(context, state, row, dirTotal),
          ]);
        },
      ),
    );
  }

  Widget _tagRow(BuildContext context, AppState state, TagTotal row, int total) {
    final tag = state.tagById(row.tagId);
    final cs = Theme.of(context).colorScheme;
    final share = total == 0 ? 0.0 : row.amount / total;
    return InkWell(
      onTap: () => state.openTransactions(
        TxnFilter(type: _type, tagId: row.tagId, untaggedOnly: row.tagId == null),
        _period,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(children: [
          Row(children: [
            TagDot(tag, size: 12),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tag?.name ?? 'No tag',
                  style: TextStyle(fontWeight: FontWeight.w600, fontStyle: tag == null ? FontStyle.italic : null)),
            ),
            Text('${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%  ',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            Text(money(row.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 22),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainer,
                  color: tag?.colorValue ?? cs.outline,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${row.count}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}
