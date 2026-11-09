import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'manual_txn_screen.dart';
import 'transaction_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Period _period = Period.thisMonth(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final presets = [
      ('This week', Period.week(now)),
      ('This month', Period.thisMonth(now)),
      ('Last month', Period.lastMonth(now)),
    ];
    final isPreset = presets.any((p) => p.$2 == _period);
    final lastScan = state.settings.lastScanMs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          state.refreshing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: 'Refresh from SMS',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => runRefresh(context),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add manual transaction',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManualTxnScreen())),
        child: const Icon(Icons.add),
      ),
      body: Reloader<(Totals, List<AccountBalance>, int, List<Txn>)>(
        deps: _period,
        load: (repo) async => (
          await repo.totals(TxnFilter(start: _period.start, end: _period.end)),
          await repo.latestBalances(),
          await repo.count(const TxnFilter(untaggedOnly: true)),
          await repo.query(TxnFilter(start: _period.start, end: _period.end), limit: 6),
        ),
        builder: (context, data) {
          final (totals, balances, untagged, recent) = data;
          final cs = Theme.of(context).colorScheme;
          return RefreshIndicator(
            onRefresh: () => runRefresh(context),
            child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final (label, p) in presets)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _period == p,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _period = p),
                        ),
                      ),
                    ChoiceChip(
                      avatar: const Icon(Icons.calendar_month, size: 16),
                      showCheckmark: false,
                      selected: !isPreset,
                      label: Text(isPreset ? 'Other…' : _period.label),
                      onSelected: (_) async {
                        final p = await pickPeriod(context);
                        if (p != null) setState(() => _period = p);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TotalsCard(totals, title: _period.label),
              ),
              if (untagged > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Card(
                    color: cs.onSurface,
                    child: ListTile(
                      textColor: cs.surface,
                      iconColor: cs.surface,
                      leading: const Icon(Icons.label_outline),
                      title: Text('$untagged transaction${untagged == 1 ? '' : 's'} need a tag'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => state.openTransactions(const TxnFilter(untaggedOnly: true), Period.all),
                    ),
                  ),
                ),
              if (balances.isNotEmpty) ...[
                const SectionTitle('Account balance (from bank SMS)'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(children: [
                      for (final b in balances)
                        ListTile(
                          dense: true,
                          title: Text([
                            b.bank ?? 'Account',
                            if (b.account != null) '${b.kind == AccountKind.card ? 'Card' : 'A/c'} ••${b.account}',
                          ].join(' · ')),
                          subtitle: Text('as of ${dateTimeFmt.format(b.asOf)}'),
                          trailing: Text(money(b.balance),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                    ]),
                  ),
                ),
              ],
              SectionTitle(
                'Recent',
                trailing: TextButton(
                  onPressed: () => state.openTransactions(const TxnFilter(), _period),
                  child: const Text('See all'),
                ),
              ),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No transactions in this period.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                for (final t in recent)
                  TxnTile(
                    txn: t,
                    showDate: true,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(id: t.id!))),
                  ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  lastScan == null
                      ? 'Never refreshed'
                      : 'Last refreshed ${dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(lastScan))}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
