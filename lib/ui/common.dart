import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../models/models.dart';
import '../services/repository.dart';
import '../state/app_state.dart';

/// Loads data and reloads it whenever app data changes (AppState.revision)
/// or [deps] changes. Keeps showing the previous data while reloading.
class Reloader<T> extends StatefulWidget {
  const Reloader({super.key, required this.load, required this.builder, this.deps});
  final Future<T> Function(Repository repo) load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? deps;

  @override
  State<Reloader<T>> createState() => _ReloaderState<T>();
}

class _ReloaderState<T> extends State<Reloader<T>> {
  int? _rev;
  Object? _deps;
  Future<T>? _future;
  T? _last;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_future == null || _rev != state.revision || _deps != widget.deps) {
      _rev = state.revision;
      _deps = widget.deps;
      _future = widget.load(state.repo);
    }
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Something went wrong: ${snap.error}')));
        }
        if (snap.hasData) _last = snap.data;
        if (_last == null) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, _last as T);
      },
    );
  }
}

class TagDot extends StatelessWidget {
  const TagDot(this.tag, {super.key, this.size = 10});
  final Tag? tag;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = tag?.colorValue;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        border: c == null ? Border.all(color: Theme.of(context).colorScheme.outline) : null,
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key});
  final Tag tag;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tag.colorValue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TagDot(tag, size: 7),
          const SizedBox(width: 4),
          Text(tag.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

class TxnTile extends StatelessWidget {
  const TxnTile({
    super.key,
    required this.txn,
    this.selected = false,
    this.selecting = false,
    this.onTap,
    this.onLongPress,
    this.showDate = false,
  });
  final Txn txn;
  final bool selected;
  final bool selecting;
  final bool showDate;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tag = state.tagById(txn.tagId);
    final cs = Theme.of(context).colorScheme;
    final sub = <String>[
      if (showDate) shortDayFmt.format(txn.occurredAt),
      timeFmt.format(txn.occurredAt),
      txn.accountLabel ?? txn.source.label,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: cs.secondaryContainer,
      selectedColor: cs.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: selecting
          ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked)
          : CircleAvatar(
              radius: 18,
              backgroundColor: cs.surfaceContainer,
              child: Icon(
                switch (txn.source) {
                  TxnSource.sms => Icons.sms_outlined,
                  TxnSource.manual => Icons.edit_outlined,
                  TxnSource.imported => Icons.file_download_outlined,
                },
                size: 18,
                color: cs.onSurface,
              ),
            ),
      title: Text(txn.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          if (tag != null) TagChip(tag),
          if (txn.note.isNotEmpty) Icon(Icons.notes, size: 14, color: cs.onSurfaceVariant),
        ]),
      ),
      trailing: Text(
        money(txn.signed, signed: true),
        style: TextStyle(
          fontWeight: txn.type == TxnType.credit ? FontWeight.w800 : FontWeight.w500,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// Debited / Credited / Net in one card.
class TotalsCard extends StatelessWidget {
  const TotalsCard(this.totals, {super.key, this.title});
  final Totals totals;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String label, int v, {bool signed = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(v, signed: signed),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Text(title!, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
          ],
          Text('Net', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(totals.net, signed: true),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            cell('Debited', totals.debit),
            cell('Credited', totals.credit),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Transactions', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 4),
                Text('${totals.count}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Groups newest-first transactions under day headers.
List<Widget> groupedTxnTiles(
  BuildContext context,
  List<Txn> txns, {
  required Widget Function(Txn) tile,
}) {
  final out = <Widget>[];
  DateTime? day;
  final cs = Theme.of(context).colorScheme;
  for (final t in txns) {
    final d = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
    if (day != d) {
      day = d;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(dayFmt.format(d),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
      ));
    }
    out.add(tile(t));
  }
  return out;
}

// --------------------------------------------------------------- pickers

Future<Period?> pickPeriod(BuildContext context, {bool allowAll = true}) async {
  final now = DateTime.now();
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (allowAll) ListTile(title: const Text('All time'), onTap: () => Navigator.pop(c, 'all')),
        ListTile(title: const Text('This week'), onTap: () => Navigator.pop(c, 'tw')),
        ListTile(title: const Text('Last week'), onTap: () => Navigator.pop(c, 'lw')),
        ListTile(title: const Text('This month'), onTap: () => Navigator.pop(c, 'tm')),
        ListTile(title: const Text('Last month'), onTap: () => Navigator.pop(c, 'lm')),
        ListTile(
            title: const Text('Choose a month…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(c, 'month')),
        ListTile(
            title: const Text('Custom dates…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(c, 'custom')),
      ]),
    ),
  );
  if (!context.mounted) return null;
  switch (choice) {
    case 'all':
      return Period.all;
    case 'tw':
      return Period.week(now);
    case 'lw':
      return Period.week(now, offset: -1);
    case 'tm':
      return Period.thisMonth(now);
    case 'lm':
      return Period.lastMonth(now);
    case 'month':
      final m = await pickMonth(context, DateTime(now.year, now.month));
      return m == null ? null : Period.month(m.year, m.month);
    case 'custom':
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      );
      return r == null ? null : Period.custom(r.start, r.end);
  }
  return null;
}

Future<DateTime?> pickMonth(BuildContext context, DateTime initial) {
  var year = initial.year;
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return showDialog<DateTime>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Row(children: [
          IconButton(onPressed: () => set(() => year--), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('$year', textAlign: TextAlign.center)),
          IconButton(onPressed: () => set(() => year++), icon: const Icon(Icons.chevron_right)),
        ]),
        content: SizedBox(
          width: 280,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            childAspectRatio: 2,
            children: [
              for (var m = 1; m <= 12; m++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: (year == initial.year && m == initial.month)
                      ? FilledButton(onPressed: () => Navigator.pop(c, DateTime(year, m)), child: Text(names[m - 1]))
                      : OutlinedButton(onPressed: () => Navigator.pop(c, DateTime(year, m)), child: Text(names[m - 1])),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Single-select tag picker. Returns null when dismissed, or a record whose
/// `id` is the chosen tag id (null = "No tag").
Future<({int? id})?> pickTag(BuildContext context, {int? current}) {
  return showModalBottomSheet<({int? id})>(
    context: context,
    isScrollControlled: true,
    builder: (c) {
      final state = c.watch<AppState>();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: const TagDot(null, size: 14),
              title: const Text('No tag'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, (id: null)),
            ),
            for (final t in state.tags)
              ListTile(
                leading: TagDot(t, size: 14),
                title: Text(t.name),
                trailing: current == t.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, (id: t.id)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New tag'),
              onTap: () async {
                final id = await showTagEditor(c);
                if (id != null && c.mounted) Navigator.pop(c, (id: id));
              },
            ),
          ]),
        ),
      );
    },
  );
}

const tagPalette = <int>[
  0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF5E35B1, 0xFF3949AB, 0xFF1E88E5,
  0xFF039BE5, 0xFF00ACC1, 0xFF00897B, 0xFF43A047, 0xFF7CB342, 0xFFC0CA33,
  0xFFFDD835, 0xFFFFB300, 0xFFFB8C00, 0xFFF4511E, 0xFF6D4C41, 0xFF757575,
];

/// Create or edit a tag. Returns the tag id when saved.
Future<int?> showTagEditor(BuildContext context, {Tag? tag}) {
  final ctrl = TextEditingController(text: tag?.name ?? '');
  var color = tag?.color ?? tagPalette[context.read<AppState>().tags.length % tagPalette.length];
  String? error;
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tag == null ? 'New tag' : 'Edit tag'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: tag == null,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: InputDecoration(labelText: 'Name', errorText: error),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in tagPalette)
              GestureDetector(
                onTap: () => set(() => color = p),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(p),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == p ? Theme.of(c).colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final state = c.read<AppState>();
              final err = await state.saveTag(Tag(id: tag?.id, name: ctrl.text, color: color));
              if (err != null) {
                set(() => error = err);
                return;
              }
              final saved = state.tags.where((t) => t.name.toLowerCase() == ctrl.text.trim().toLowerCase()).firstOrNull;
              if (c.mounted) Navigator.pop(c, saved?.id);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------- refresh UX

/// Runs an SMS refresh and reports the outcome. Shared by the Home button,
/// Settings and the notification's Refresh action.
Future<void> runRefresh(BuildContext context, {DateTime? since}) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final r = await state.refreshFromSms(since: since);
  if (!context.mounted) return;
  switch (r.status) {
    case RefreshStatus.ok:
      messenger.showSnackBar(SnackBar(
        content: Text(r.added == 0
            ? 'Up to date. No new transactions.'
            : '${r.added} new transaction${r.added == 1 ? '' : 's'} imported'),
        action: r.added == 0
            ? null
            : SnackBarAction(
                label: 'Tag them',
                onPressed: () => state.openTransactions(
                  const TxnFilter(untaggedOnly: true),
                  Period.all,
                ),
              ),
      ));
    case RefreshStatus.busy:
      break;
    case RefreshStatus.permissionDenied:
      messenger.showSnackBar(const SnackBar(content: Text('SMS permission is needed to import transactions.')));
    case RefreshStatus.permissionPermanentlyDenied:
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Allow SMS access'),
          content: const Text(
              'SMS access was turned off for this app. Open settings and allow "SMS" to import bank transactions.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open settings')),
          ],
        ),
      );
      if (open == true) await openAppSettings();
    case RefreshStatus.error:
      messenger.showSnackBar(SnackBar(content: Text('Could not read SMS: ${r.error ?? 'unknown error'}')));
  }
}

Future<bool> confirm(BuildContext context,
    {required String title, required String message, String action = 'Confirm'}) async {
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      ) ??
      false;
}
