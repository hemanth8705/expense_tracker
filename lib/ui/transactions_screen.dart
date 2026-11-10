import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'export_sheet.dart';
import 'manual_txn_screen.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  Period _period = Period.thisMonth(DateTime.now());
  late TxnFilter _filter = TxnFilter(start: _period.start, end: _period.end);
  final Set<int> _selected = {};
  List<Txn> _visible = const [];
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _takePending();
  }

  void _takePending() {
    final v = context.read<AppState>().takePendingTxnView();
    if (v == null) return;
    _period = v.period;
    _filter = v.filter;
    _selected.clear();
  }

  void _setPeriod(Period p) => setState(() {
        _period = p;
        _filter = _filter.copyWith(start: p.start, end: p.end);
        _selected.clear();
      });

  void _setFilter(TxnFilter f) => setState(() {
        _filter = f;
        _selected.clear();
      });

  bool get _hasExtraFilters =>
      _filter.type != null ||
      _filter.source != null ||
      _filter.bank != null ||
      _filter.tagId != null ||
      _filter.untaggedOnly;

  void _toggle(Txn t) => setState(() {
        if (!_selected.remove(t.id)) _selected.add(t.id!);
      });

  Future<void> _bulkTag() async {
    final state = context.read<AppState>();
    final r = await pickTag(context);
    if (r == null) return;
    final n = _selected.length;
    await state.setTag(_selected.toList(), r.id);
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tag updated on $n transaction${n == 1 ? '' : 's'}')));
  }

  Future<void> _bulkArchive() async {
    final state = context.read<AppState>();
    final ids = _selected.toList();
    final n = await state.archive(ids);
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Archived $n transaction${n == 1 ? '' : 's'}'),
      action: SnackBarAction(label: 'Undo', onPressed: () => state.restore(ids)),
    ));
  }

  Future<void> _archiveRange() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Archive transactions between',
    );
    if (r == null || !mounted) return;
    final p = Period.custom(r.start, r.end);
    final n = await state.repo.count(TxnFilter(start: p.start, end: p.end));
    if (!mounted) return;
    if (n == 0) {
      messenger.showSnackBar(const SnackBar(content: Text('No transactions in that range')));
      return;
    }
    final ok = await confirm(context,
        title: 'Archive $n transaction${n == 1 ? '' : 's'}?',
        message: 'Everything from ${p.label} will be hidden from lists, totals, reports, the widget and exports. '
            'Archived SMS are never imported again. You can restore them from Settings › Archived.',
        action: 'Archive');
    if (!ok) return;
    final done = await state.archiveRange(p.start!, p.end!);
    messenger.showSnackBar(SnackBar(content: Text('Archived $done transaction${done == 1 ? '' : 's'}')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.pendingTxnView != null) _takePending();
    final selecting = _selected.isNotEmpty;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() => _selected.addAll(_visible.map((t) => t.id!))),
                  ),
                  IconButton(tooltip: 'Set tag', icon: const Icon(Icons.label_outline), onPressed: _bulkTag),
                  IconButton(tooltip: 'Archive', icon: const Icon(Icons.archive_outlined), onPressed: _bulkArchive),
                ],
              )
            : AppBar(
                title: _searching
                    ? TextField(
                        controller: _search,
                        autofocus: true,
                        decoration: const InputDecoration(
                            hintText: 'Search name, note, bank, SMS', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                        onChanged: (v) => _setFilter(_filter.copyWith(search: v)),
                      )
                    : const Text('Transactions'),
                actions: [
                  IconButton(
                    icon: Icon(_searching ? Icons.close : Icons.search),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) {
                        _search.clear();
                        _filter = _filter.copyWith(search: '');
                      }
                    }),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'archive') _archiveRange();
                      if (v == 'export') showExportSheet(context, _period);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'archive', child: Text('Archive by date range…')),
                      PopupMenuItem(value: 'export', child: Text('Export…')),
                    ],
                  ),
                ],
              ),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton(
                tooltip: 'Add manual transaction',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManualTxnScreen())),
                child: const Icon(Icons.add),
              ),
        body: Column(children: [
          _FilterBar(
            period: _period,
            filter: _filter,
            onPeriod: _setPeriod,
            onFilter: _setFilter,
            showClear: _hasExtraFilters,
          ),
          Expanded(
            child: Reloader<(List<Txn>, Totals)>(
              deps: _filter,
              load: (repo) async => (await repo.query(_filter), await repo.totals(_filter)),
              builder: (context, data) {
                final (txns, totals) = data;
                _visible = txns;
                if (txns.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions',
                    message: state.settings.lastScanMs == null
                        ? 'Tap refresh on Home to import bank SMS.'
                        : 'Nothing matches these filters.',
                  );
                }
                final cs = Theme.of(context).colorScheme;
                return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      '${totals.count} txns · Debited ${money(totals.debit)} · Credited ${money(totals.credit)} · Net ${money(totals.net, signed: true)}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  ...groupedTxnTiles(context, txns,
                      tile: (t) => TxnTile(
                            txn: t,
                            selecting: selecting,
                            selected: _selected.contains(t.id),
                            onLongPress: () => _toggle(t),
                            onTap: selecting
                                ? () => _toggle(t)
                                : () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => TransactionDetailScreen(id: t.id!))),
                          )),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.period,
    required this.filter,
    required this.onPeriod,
    required this.onFilter,
    required this.showClear,
  });
  final Period period;
  final TxnFilter filter;
  final ValueChanged<Period> onPeriod;
  final ValueChanged<TxnFilter> onFilter;
  final bool showClear;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tagLabel = filter.untaggedOnly
        ? 'No tag'
        : filter.tagId != null
            ? (state.tagById(filter.tagId)?.name ?? 'Tag')
            : 'Tag';

    Widget menuChip<T>({
      required String label,
      required bool active,
      required List<(String, T)> options,
      required ValueChanged<T> onSelect,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: PopupMenuButton<int>(
            onSelected: (i) => onSelect(options[i].$2),
            itemBuilder: (_) => [
              for (var i = 0; i < options.length; i++) PopupMenuItem(value: i, child: Text(options[i].$1)),
            ],
            child: Chip(
              label: Text(label),
              backgroundColor: active ? Theme.of(context).colorScheme.onSurface : null,
              labelStyle: TextStyle(
                color: active ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface,
              ),
              deleteIcon: Icon(Icons.arrow_drop_down,
                  color: active ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface),
              onDeleted: () {}, // shows the dropdown arrow; taps open the menu
            ),
          ),
        );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 16),
              label: Text(period.label),
              onPressed: () async {
                final p = await pickPeriod(context);
                if (p != null) onPeriod(p);
              },
            ),
          ),
          menuChip<TxnType?>(
            label: switch (filter.type) {
              null => 'Type',
              TxnType.debit => 'Debits',
              TxnType.credit => 'Credits',
            },
            active: filter.type != null,
            options: const [('All', null), ('Debits', TxnType.debit), ('Credits', TxnType.credit)],
            onSelect: (v) => onFilter(filter.copyWith(type: v)),
          ),
          menuChip<int?>(
            label: tagLabel,
            active: filter.tagId != null || filter.untaggedOnly,
            options: [
              ('All', null),
              ('No tag', -1),
              for (final t in state.tags) (t.name, t.id),
            ],
            onSelect: (v) => onFilter(v == -1
                ? filter.copyWith(untaggedOnly: true, tagId: null)
                : filter.copyWith(untaggedOnly: false, tagId: v)),
          ),
          menuChip<TxnSource?>(
            label: filter.source?.label ?? 'Source',
            active: filter.source != null,
            options: [('All', null), for (final s in TxnSource.values) (s.label, s)],
            onSelect: (v) => onFilter(filter.copyWith(source: v)),
          ),
          FutureBuilder<List<String>>(
            future: state.repo.banks(),
            builder: (context, snap) => menuChip<String?>(
              label: filter.bank ?? 'Bank',
              active: filter.bank != null,
              options: [('All', null), for (final b in snap.data ?? const <String>[]) (b, b)],
              onSelect: (v) => onFilter(filter.copyWith(bank: v)),
            ),
          ),
          if (showClear)
            TextButton(
              onPressed: () => onFilter(TxnFilter(start: period.start, end: period.end, search: filter.search)),
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}
