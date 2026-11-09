import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/period.dart';
import '../models/models.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import 'common.dart';

Future<void> showExportSheet(BuildContext context, Period initial) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExportSheet(initial: initial),
    );

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.initial});
  final Period initial;
  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late Period _period = widget.initial;
  ExportFormat _format = ExportFormat.xlsx;
  bool _busy = false;

  Future<void> _run({required bool share}) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final file = await ExportService.build(state.repo, _period, state.tags, _format);
      if (share) {
        await ExportService.share(file);
        nav.pop();
      } else {
        final saved = await ExportService.saveToDevice(file);
        if (saved) {
          nav.pop();
          messenger.showSnackBar(SnackBar(content: Text('Saved ${file.name}')));
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Export', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Archived transactions are not included.', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month),
            title: Text(_period.label),
            subtitle: Reloader<int>(
              deps: _period,
              load: (repo) => repo.count(TxnFilter(start: _period.start, end: _period.end)),
              builder: (_, n) => Text('$n transaction${n == 1 ? '' : 's'}'),
            ),
            trailing: const Text('Change'),
            onTap: () async {
              final p = await pickPeriod(context);
              if (p != null) setState(() => _period = p);
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            segments: const [
              ButtonSegment(value: ExportFormat.xlsx, label: Text('Excel (.xlsx)')),
              ButtonSegment(value: ExportFormat.csv, label: Text('CSV')),
            ],
            selected: {_format},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(share: true),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _run(share: false),
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: const Text('Save'),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
