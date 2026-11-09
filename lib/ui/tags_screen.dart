import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  Future<void> _delete(BuildContext context, Tag t) async {
    final state = context.read<AppState>();
    final used = await state.repo.tagUsage(t.id!);
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      title: 'Delete "${t.name}"?',
      message: used == 0
          ? 'No transactions use this tag.'
          : '$used transaction${used == 1 ? '' : 's'} will move to "No tag". The transactions themselves are kept.',
      action: 'Delete',
    );
    if (ok) await state.deleteTag(t.id!);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New tag',
        onPressed: () => showTagEditor(context),
        child: const Icon(Icons.add),
      ),
      body: state.tags.isEmpty
          ? const EmptyState(
              icon: Icons.sell_outlined,
              title: 'No tags yet',
              message: 'Create tags like Food, Rent or Travel to see where your money goes.',
            )
          : ListView(children: [
              for (final t in state.tags)
                ListTile(
                  leading: TagDot(t, size: 16),
                  title: Text(t.name),
                  onTap: () => showTagEditor(context, tag: t),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, t),
                  ),
                ),
            ]),
    );
  }
}
