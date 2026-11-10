import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../services/home_widget_service.dart';
import '../services/settings.dart';
import '../state/app_state.dart';
import 'archive_screen.dart';
import 'common.dart';
import 'export_sheet.dart';
import 'import_flow.dart';
import 'tags_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final cs = Theme.of(context).colorScheme;
    final lastScan = s.lastScanMs;
    final reminder = TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const SectionTitle('SMS'),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Refresh now'),
          subtitle: Text(lastScan == null
              ? 'Never refreshed'
              : 'Last: ${dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(lastScan))}'),
          trailing: state.refreshing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onTap: state.refreshing ? null : () => runRefresh(context),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Import older SMS'),
          subtitle: const Text('Read the inbox from a date you choose. Already-imported and archived SMS are skipped.'),
          onTap: state.refreshing
              ? null
              : () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime(now.year - 1, now.month, now.day),
                    firstDate: DateTime(2000),
                    lastDate: now,
                    helpText: 'Import SMS received since',
                  );
                  if (d != null && context.mounted) await runRefresh(context, since: d);
                },
        ),

        const SectionTitle('Daily reminder'),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_none),
          title: const Text('Remind me to refresh'),
          subtitle: const Text('Notification with a Refresh button'),
          value: s.reminderEnabled,
          onChanged: (v) => state.setReminder(enabled: v),
        ),
        ListTile(
          enabled: s.reminderEnabled,
          leading: const Icon(Icons.schedule),
          title: const Text('Time'),
          trailing: Text(reminder.format(context), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: reminder);
            if (t != null) await state.setReminder(hour: t.hour, minute: t.minute);
          },
        ),

        const SectionTitle('Home screen widget'),
        ListTile(
          leading: const Icon(Icons.date_range),
          title: const Text('Period'),
          trailing: Text(
            s.widgetPeriod == WidgetPeriod.specificMonth ? monthFmt.format(s.widgetMonth) : s.widgetPeriod.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: () async {
            final v = await showModalBottomSheet<WidgetPeriod>(
              context: context,
              builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final p in WidgetPeriod.values)
                    ListTile(
                      title: Text(p.label),
                      trailing: p == s.widgetPeriod ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(c, p),
                    ),
                ]),
              ),
            );
            if (v == null || !context.mounted) return;
            if (v == WidgetPeriod.specificMonth) {
              final m = await pickMonth(context, s.widgetMonth);
              if (m == null) return;
              await state.updateWidgetSettings((x) {
                x.widgetMonth = m;
                x.widgetPeriod = v;
              });
            } else {
              await state.updateWidgetSettings((x) => x.widgetPeriod = v);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: const Text('Transactions'),
          trailing: Text(
            switch (s.widgetTagId) {
              null => 'All',
              -1 => 'No tag only',
              final id => state.tagById(id)?.name ?? 'All',
            },
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: () async {
            final v = await showModalBottomSheet<({int? id})>(
              context: context,
              builder: (c) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  ListTile(title: const Text('All'), onTap: () => Navigator.pop(c, (id: null))),
                  ListTile(title: const Text('No tag only'), onTap: () => Navigator.pop(c, (id: -1))),
                  for (final t in state.tags)
                    ListTile(leading: TagDot(t, size: 14), title: Text(t.name), onTap: () => Navigator.pop(c, (id: t.id))),
                ]),
              ),
            );
            if (v != null) await state.updateWidgetSettings((x) => x.widgetTagId = v.id);
          },
        ),
        SwitchListTile(
          title: const Text('Show debited'),
          value: s.widgetShowDebit,
          onChanged: (v) => state.updateWidgetSettings((x) => x.widgetShowDebit = v),
        ),
        SwitchListTile(
          title: const Text('Show credited'),
          value: s.widgetShowCredit,
          onChanged: (v) => state.updateWidgetSettings((x) => x.widgetShowCredit = v),
        ),
        SwitchListTile(
          title: const Text('Show net'),
          value: s.widgetShowNet,
          onChanged: (v) => state.updateWidgetSettings((x) => x.widgetShowNet = v),
        ),
        FutureBuilder<bool>(
          future: HomeWidgetService.canPin(),
          builder: (context, snap) => snap.data == true
              ? ListTile(
                  leading: const Icon(Icons.add_to_home_screen),
                  title: const Text('Add widget to home screen'),
                  onTap: HomeWidgetService.pin,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text('To add it: long-press your home screen › Widgets › Expense Tracker.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ),
        ),

        const SectionTitle('Data'),
        ListTile(
          leading: const Icon(Icons.sell_outlined),
          title: const Text('Tags'),
          subtitle: Text('${state.tags.length} tag${state.tags.length == 1 ? '' : 's'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Archived'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchiveScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Export CSV / Excel'),
          onTap: () => showExportSheet(context, Period.thisMonth(DateTime.now())),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Import from Excel / CSV'),
          subtitle: const Text('Restore a file exported from this app. Tags and notes come back; duplicates are skipped.'),
          onTap: () => runImport(context),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'All data is stored only on this phone. Uninstalling the app deletes it, so export to Excel regularly; '
            'you can import that file back on a new install.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}
