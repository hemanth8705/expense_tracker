import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/import_service.dart';
import '../state/app_state.dart';

/// Pick an exported .xlsx/.csv, show what will happen, then import.
Future<void> runImport(BuildContext context) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);

  final List<PlatformFile> picked;
  try {
    // FileType.any: some Android file managers don't map .xlsx to a MIME
    // type, so filtering by extension can hide the file. Checked below.
    picked = await FilePicker.pickFiles(dialogTitle: 'Choose an exported Excel or CSV file');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker: $e')));
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final file = picked.first;

  final ImportFileResult parsed;
  final ImportOutcome preview;
  try {
    parsed = ImportService.parse(await file.readAsBytes(), file.name);
    preview = await state.importRows(parsed, dryRun: true);
  } catch (e) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cannot import this file'),
        content: Text('$e'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    return;
  }
  if (!context.mounted) return;

  final rows = parsed.rows;
  final first = rows.isEmpty ? null : rows.map((r) => r.at).reduce((a, b) => a.isBefore(b) ? a : b);
  final last = rows.isEmpty ? null : rows.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b);
  String d(DateTime x) => '${x.day}/${x.month}/${x.year}';

  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${rows.length} transaction${rows.length == 1 ? '' : 's'} in the file'
              '${first == null ? '' : ' (${d(first)} – ${d(last!)})'}.'),
          const SizedBox(height: 12),
          _line(Icons.add, '${preview.added} will be imported as "Imported"'),
          if (preview.duplicates > 0)
            _line(Icons.block, '${preview.duplicates} already in the app, skipped'),
          if (preview.tagsCreated > 0)
            _line(Icons.sell_outlined, '${preview.tagsCreated} new tag${preview.tagsCreated == 1 ? '' : 's'} will be created'),
          if (preview.errors.isNotEmpty) ...[
            _line(Icons.error_outline, '${preview.errors.length} row${preview.errors.length == 1 ? '' : 's'} could not be read:'),
            for (final e in preview.errors.take(5))
              Padding(padding: const EdgeInsets.only(left: 30, top: 2), child: Text(e, style: const TextStyle(fontSize: 12))),
            if (preview.errors.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text('…and ${preview.errors.length - 5} more', style: const TextStyle(fontSize: 12)),
              ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: preview.added == 0 ? null : () => Navigator.pop(c, true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (go != true) return;

  final result = await state.importRows(parsed);
  messenger.showSnackBar(SnackBar(
    content: Text('Imported ${result.added} transaction${result.added == 1 ? '' : 's'}'
        '${result.duplicates > 0 ? ', skipped ${result.duplicates} duplicate${result.duplicates == 1 ? '' : 's'}' : ''}'),
  ));
}

Widget _line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    );
