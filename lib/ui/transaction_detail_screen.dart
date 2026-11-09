import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'manual_txn_screen.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final int id;
  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final _note = TextEditingController();
  bool _noteLoaded = false;
  Timer? _debounce;
  late final AppState _state = context.read<AppState>();

  @override
  void dispose() {
    // Flush a pending note edit when leaving the screen.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _state.setNote(widget.id, _note.text);
    }
    _note.dispose();
    super.dispose();
  }

  void _onNoteChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _state.setNote(widget.id, v));
  }

  Future<void> _archive(Txn t) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await _state.archive([t.id!]);
    nav.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Archived. Hidden from lists, totals and reports.'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _state.restore([t.id!])),
    ));
  }

  Future<void> _restore(Txn t) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await _state.restore([t.id!]);
    nav.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Restored')));
  }

  Future<void> _delete(Txn t) async {
    final ok = await confirm(context,
        title: 'Delete this entry?',
        message: 'This manual transaction will be permanently deleted.',
        action: 'Delete');
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await _state.deleteManual([t.id!]);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Reloader<Txn?>(
      load: (repo) => repo.byId(widget.id),
      builder: (context, t) {
        if (t == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, title: 'Transaction not found'));
        }
        if (!_noteLoaded) {
          _note.text = t.note;
          _noteLoaded = true;
        }
        final state = context.watch<AppState>();
        final tag = state.tagById(t.tagId);
        final cs = Theme.of(context).colorScheme;

        Widget info(String k, String? v) => v == null || v.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 110, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
                  Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
                ]),
              );

        return Scaffold(
          appBar: AppBar(
            title: Text(t.archived ? 'Archived' : (t.isSms ? 'SMS transaction' : 'Manual transaction')),
            actions: [
              if (!t.isSms && !t.archived)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ManualTxnScreen(existing: t))),
                ),
              if (!t.isSms)
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(t)),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text(t.type == TxnType.debit ? 'Debited' : 'Credited', style: TextStyle(color: cs.onSurfaceVariant)),
            Text(money(t.signed, signed: true),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
            Text(dateTimeFmt.format(t.occurredAt), style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(children: [
                  info(t.type == TxnType.debit ? 'Paid to' : 'Received from', t.counterparty),
                  info('Bank', t.bank),
                  info(t.accountKind == AccountKind.card ? 'Card' : 'Account', t.account == null ? null : '••${t.account}'),
                  info('Balance after', t.balance == null ? null : money(t.balance!)),
                  info('Source', t.isSms ? 'SMS from ${t.smsSender}' : 'Added manually'),
                  if (t.archived && t.archivedAt != null) info('Archived on', dateTimeFmt.format(t.archivedAt!)),
                ]),
              ),
            ),
            const SectionTitle('Tag'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('No tag'),
                selected: tag == null,
                showCheckmark: false,
                onSelected: (_) => state.setTag([t.id!], null),
              ),
              for (final tg in state.tags)
                ChoiceChip(
                  avatar: TagDot(tg),
                  label: Text(tg.name),
                  selected: tg.id == t.tagId,
                  showCheckmark: false,
                  onSelected: (_) => state.setTag([t.id!], tg.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('New tag'),
                onPressed: () async {
                  final id = await showTagEditor(context);
                  if (id != null) await state.setTag([t.id!], id);
                },
              ),
            ]),
            const SectionTitle('Note'),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Add a note'),
              onChanged: _onNoteChanged,
            ),
            if (t.smsBody != null) ...[
              SectionTitle(
                'Original SMS',
                trailing: IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: t.smsBody!)),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
                child: SelectableText(t.smsBody!, style: const TextStyle(height: 1.4)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: t.archived
                  ? FilledButton.icon(
                      onPressed: () => _restore(t),
                      icon: const Icon(Icons.unarchive_outlined),
                      label: const Text('Restore'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _archive(t),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archive'),
                    ),
            ),
            if (!t.archived)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Archiving hides this from every list, total, report, the widget and exports. '
                  '${t.isSms ? 'This SMS will not be imported again. ' : ''}You can restore it from Settings › Archived.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
          ]),
        );
      },
    );
  }
}
