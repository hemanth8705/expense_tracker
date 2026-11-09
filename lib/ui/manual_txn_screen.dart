import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';

/// Add or edit a manual (non-SMS) transaction.
class ManualTxnScreen extends StatefulWidget {
  const ManualTxnScreen({super.key, this.existing});
  final Txn? existing;
  @override
  State<ManualTxnScreen> createState() => _ManualTxnScreenState();
}

class _ManualTxnScreenState extends State<ManualTxnScreen> {
  late TxnType _type = widget.existing?.type ?? TxnType.debit;
  late final _amount = TextEditingController(
      text: widget.existing == null ? '' : (widget.existing!.amount / 100).toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), ''));
  late final _party = TextEditingController(text: widget.existing?.counterparty ?? '');
  late final _account = TextEditingController(text: widget.existing?.bank ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _when = widget.existing?.occurredAt ?? DateTime.now();
  late int? _tagId = widget.existing?.tagId;
  String? _amountError;
  bool _saving = false;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    setState(() => _when = DateTime(d.year, d.month, d.day, t?.hour ?? _when.hour, t?.minute ?? _when.minute));
  }

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    if (amount == null) {
      setState(() => _amountError = 'Enter an amount greater than 0');
      return;
    }
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final e = widget.existing;
    final txn = Txn(
      id: e?.id,
      source: TxnSource.manual,
      type: _type,
      amount: amount,
      occurredAt: _when,
      bank: _account.text.trim().isEmpty ? null : _account.text.trim(),
      counterparty: _party.text.trim().isEmpty ? null : _party.text.trim(),
      tagId: _tagId,
      note: _note.text.trim(),
      createdAt: e?.createdAt ?? DateTime.now(),
    );
    if (e == null) {
      await state.addManual(txn);
    } else {
      await state.updateManual(txn);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tag = state.tagById(_tagId);
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add transaction' : 'Edit transaction')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<TxnType>(
          segments: const [
            ButtonSegment(value: TxnType.debit, label: Text('Debit (money out)')),
            ButtonSegment(value: TxnType.credit, label: Text('Credit (money in)')),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: widget.existing == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          decoration: InputDecoration(prefixText: '₹ ', labelText: 'Amount', errorText: _amountError),
          onChanged: (_) => _amountError == null ? null : setState(() => _amountError = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _party,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: _type == TxnType.debit ? 'Paid to' : 'Received from'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _account,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Account / method (optional)', hintText: 'Cash, HDFC, Card…'),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(dateTimeFmt.format(_when)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickDate,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: TagDot(tag, size: 14),
          title: Text(tag?.name ?? 'No tag'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final r = await pickTag(context, current: _tagId);
            if (r != null) setState(() => _tagId = r.id);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ),
      ]),
    );
  }
}
