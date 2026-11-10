import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/dedupe.dart';
import '../core/period.dart';
import '../models/models.dart';
import '../services/import_service.dart';
import '../services/home_widget_service.dart';
import '../services/notifications.dart';
import '../services/repository.dart';
import '../services/settings.dart';
import '../services/sms_parser.dart';
import '../services/sms_reader.dart';

enum RefreshStatus { ok, permissionDenied, permissionPermanentlyDenied, busy, error }

class RefreshResult {
  final RefreshStatus status;
  final int scanned;
  final int financial;
  final int added;
  final String? error;
  const RefreshResult(this.status, {this.scanned = 0, this.financial = 0, this.added = 0, this.error});
}

class ImportOutcome {
  final int added;
  final int duplicates;
  final int tagsCreated;
  final List<String> errors;
  const ImportOutcome({required this.added, required this.duplicates, required this.tagsCreated, required this.errors});
}

/// Single place that performs every mutation and its side effects.
///
/// After ANY data change, [_changed] runs, which:
///   1. bumps [revision] so every open screen reloads its query,
///   2. reloads tags (names/colours shown everywhere),
///   3. recomputes and pushes the home-screen widget.
/// Screens never write to the repository directly.
class AppState extends ChangeNotifier {
  AppState(this.repo, this.settings);

  final Repository repo;
  final Settings settings;

  /// Changes on every data mutation; screens reload when it changes.
  int revision = 0;
  List<Tag> tags = const [];
  bool refreshing = false;

  /// What the Transactions tab should switch to (set from Home / Reports).
  ({TxnFilter filter, Period period})? pendingTxnView;

  /// Days of overlap re-scanned on each refresh, in case of late-arriving SMS.
  /// Duplicates are dropped by sms_key, so the overlap is harmless.
  static const _overlap = Duration(days: 2);
  static const firstImportWindow = Duration(days: 90);

  Future<void> init() async {
    tags = await repo.tags();
    await _syncWidget();
    // Re-arm the daily reminder (covers timezone changes and app updates).
    if (settings.onboarded && settings.reminderEnabled) {
      try {
        await Notifications.scheduleDaily(settings.reminderHour, settings.reminderMinute);
      } catch (e) {
        debugPrint('Reminder scheduling failed: $e');
      }
    }
  }

  Tag? tagById(int? id) => id == null ? null : tags.where((t) => t.id == id).firstOrNull;

  Future<void> _changed() async {
    revision++;
    tags = await repo.tags();
    notifyListeners();
    await _syncWidget();
  }

  Future<void> _syncWidget() => HomeWidgetService.update(repo, settings, tags);

  /// Called on app resume so "this month" in the widget rolls over.
  Future<void> onResume() => _syncWidget();

  /// Switches to the Transactions tab with [filter]. [period] supplies the
  /// date range label; its start/end override the filter's.
  void openTransactions(TxnFilter filter, Period period) {
    pendingTxnView = (filter: filter.copyWith(start: period.start, end: period.end), period: period);
    notifyListeners();
  }

  ({TxnFilter filter, Period period})? takePendingTxnView() {
    final v = pendingTxnView;
    pendingTxnView = null;
    return v;
  }

  // ------------------------------------------------------------- SMS import


  /// Reads the inbox and imports new debit/credit SMS.
  /// [since] overrides the automatic window (used by "Import older SMS").
  Future<RefreshResult> refreshFromSms({DateTime? since}) async {
    if (refreshing) return const RefreshResult(RefreshStatus.busy);

    var perm = await Permission.sms.status;
    if (!perm.isGranted) perm = await Permission.sms.request();
    if (perm.isPermanentlyDenied) {
      return const RefreshResult(RefreshStatus.permissionPermanentlyDenied);
    }
    if (!perm.isGranted) return const RefreshResult(RefreshStatus.permissionDenied);

    refreshing = true;
    notifyListeners();
    final scanStartedAt = DateTime.now();
    try {
      final last = settings.lastScanMs;
      final from = since ??
          (last == null
              ? scanStartedAt.subtract(firstImportWindow)
              : DateTime.fromMillisecondsSinceEpoch(last).subtract(_overlap));

      final inbox = await SmsReader.readInbox(since: from);
      final candidates = <String, Txn>{};
      var financial = 0;
      for (final sms in inbox) {
        final parsed = SmsParser.parse(sender: sms.address, body: sms.body);
        if (parsed == null) continue;
        financial++;
        final key = smsDedupeKey(sms.address, sms.date, sms.body);
        candidates[key] = Txn(
          source: TxnSource.sms,
          type: parsed.type,
          amount: parsed.amount,
          occurredAt: sms.date,
          bank: parsed.bank,
          account: parsed.account,
          accountKind: parsed.accountKind,
          counterparty: parsed.counterparty,
          balance: parsed.balance,
          smsKey: key,
          smsSender: sms.address,
          smsBody: sms.body,
          createdAt: scanStartedAt,
        );
      }

      // Skip anything already stored, including archived rows.
      final existing = await repo.existingSmsKeys(candidates.keys);
      final fresh = candidates.entries
          .where((e) => !existing.contains(e.key))
          .map((e) => e.value)
          .toList();
      final added = await repo.insertSmsTxns(fresh);

      // Never move the scan marker backwards (e.g. after importing older SMS).
      if (last == null || scanStartedAt.millisecondsSinceEpoch > last) {
        settings.lastScanMs = scanStartedAt.millisecondsSinceEpoch;
      }
      refreshing = false;
      await _changed();
      return RefreshResult(RefreshStatus.ok,
          scanned: inbox.length, financial: financial, added: added);
    } on PlatformException catch (e) {
      refreshing = false;
      notifyListeners();
      return RefreshResult(
          e.code == 'PERMISSION' ? RefreshStatus.permissionDenied : RefreshStatus.error,
          error: e.message);
    } catch (e) {
      refreshing = false;
      notifyListeners();
      return RefreshResult(RefreshStatus.error, error: e.toString());
    }
  }

  // ----------------------------------------------------------------- import

  /// Imports rows from an exported file as source = imported.
  ///
  /// Duplicates are skipped, so importing the same file twice, or importing
  /// and then refreshing SMS, never double-counts:
  ///  * rows with SMS text use the same key as an SMS read from the inbox,
  ///  * rows without SMS text use an entry key, and are also skipped when a
  ///    manual entry with the same type, amount and minute already exists.
  /// Missing tags are created (colour from the file's Tags sheet if present).
  /// With [dryRun] nothing is written; the counts are what would happen.
  Future<ImportOutcome> importRows(ImportFileResult file, {bool dryRun = false}) async {
    final now = DateTime.now();
    final existingTags = {for (final t in tags) t.name.toLowerCase(): t};
    final newTagNames = <String, String>{}; // lower -> display
    for (final r in file.rows) {
      final name = r.tag?.trim();
      if (name == null || name.isEmpty) continue;
      if (!existingTags.containsKey(name.toLowerCase())) newTagNames[name.toLowerCase()] ??= name;
    }

    final keyed = <String, ImportRow>{};
    var duplicates = 0;
    for (final r in file.rows) {
      final key = r.hasSms
          ? smsDedupeKey(r.smsSender!, r.at, r.smsBody!)
          : entryDedupeKey(r.type, r.amount, r.at, r.counterparty, r.note);
      if (keyed.containsKey(key)) {
        duplicates++; // repeated inside the file itself
      } else {
        keyed[key] = r;
      }
    }
    final stored = await repo.existingSmsKeys(keyed.keys);
    final fresh = <String, ImportRow>{};
    for (final e in keyed.entries) {
      if (stored.contains(e.key) ||
          (!e.value.hasSms && await repo.hasMatchingManual(e.value.type, e.value.amount, e.value.at))) {
        duplicates++;
      } else {
        fresh[e.key] = e.value;
      }
    }

    if (dryRun || fresh.isEmpty) {
      return ImportOutcome(
          added: fresh.length, duplicates: duplicates, tagsCreated: newTagNames.length, errors: file.errors);
    }

    // Create tags first so rows can reference them.
    var palette = tags.length;
    for (final name in newTagNames.values) {
      final color = file.tagColors[name.toLowerCase()] ?? _palette[palette++ % _palette.length];
      await repo.insertTag(Tag(name: name, color: color));
    }
    final tagIds = {for (final t in await repo.tags()) t.name.toLowerCase(): t.id};

    final txns = [
      for (final e in fresh.entries)
        Txn(
          source: TxnSource.imported,
          type: e.value.type,
          amount: e.value.amount,
          occurredAt: e.value.at,
          bank: e.value.bank,
          account: e.value.account,
          accountKind: e.value.accountKind,
          counterparty: e.value.counterparty,
          balance: e.value.balance,
          tagId: e.value.tag == null ? null : tagIds[e.value.tag!.trim().toLowerCase()],
          note: e.value.note,
          smsKey: e.key,
          smsSender: e.value.hasSms ? e.value.smsSender : null,
          smsBody: e.value.hasSms ? e.value.smsBody : null,
          createdAt: now,
        ),
    ];
    final added = await repo.insertImported(txns);
    await _changed();
    return ImportOutcome(
      added: added,
      duplicates: duplicates + (txns.length - added),
      tagsCreated: newTagNames.length,
      errors: file.errors,
    );
  }

  static const _palette = <int>[
    0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFB8C00, 0xFF8E24AA, 0xFF00ACC1,
    0xFFFDD835, 0xFF6D4C41, 0xFFD81B60, 0xFF3949AB, 0xFF7CB342, 0xFF757575,
  ];

  // ----------------------------------------------------------- transactions

  Future<void> addManual(Txn t) async {
    await repo.insertManual(t);
    await _changed();
  }

  Future<void> updateManual(Txn t) async {
    await repo.updateManual(t);
    await _changed();
  }

  Future<void> deleteManual(List<int> ids) async {
    if (ids.isEmpty) return;
    await repo.deleteManual(ids);
    await _changed();
  }

  Future<void> setTag(List<int> ids, int? tagId) async {
    if (ids.isEmpty) return;
    await repo.setTag(ids, tagId);
    await _changed();
  }

  Future<void> setNote(int id, String note) async {
    await repo.setNote(id, note.trim());
    await _changed();
  }

  Future<int> archive(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final n = await repo.setArchived(ids, true);
    await _changed();
    return n;
  }

  Future<int> restore(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final n = await repo.setArchived(ids, false);
    await _changed();
    return n;
  }

  Future<int> archiveRange(DateTime start, DateTime end) async {
    final n = await repo.archiveRange(start, end);
    await _changed();
    return n;
  }

  // ------------------------------------------------------------------- tags

  /// Returns an error message, or null on success.
  Future<String?> saveTag(Tag t) async {
    final name = t.name.trim();
    if (name.isEmpty) return 'Name is required';
    if (await repo.tagNameExists(name, exceptId: t.id)) return 'A tag with this name already exists';
    final clean = Tag(id: t.id, name: name, color: t.color);
    if (t.id == null) {
      await repo.insertTag(clean);
    } else {
      await repo.updateTag(clean);
    }
    await _changed();
    return null;
  }

  Future<void> deleteTag(int id) async {
    await repo.deleteTag(id);
    if (settings.widgetTagId == id) settings.widgetTagId = null;
    await _changed();
  }

  // --------------------------------------------------------------- settings

  /// Turns on the default 9 PM reminder and swaps to the main app. The shell
  /// then runs the first import (last 3 months).
  Future<void> completeOnboarding() async {
    await setReminder(enabled: true);
    settings.onboarded = true;
    notifyListeners();
  }

  Future<void> setReminder({bool? enabled, int? hour, int? minute}) async {
    if (enabled != null) settings.reminderEnabled = enabled;
    if (hour != null && minute != null) settings.setReminderTime(hour, minute);
    if (settings.reminderEnabled) {
      await Notifications.requestPermission();
      await Notifications.scheduleDaily(settings.reminderHour, settings.reminderMinute);
    } else {
      await Notifications.cancelDaily();
    }
    notifyListeners();
  }

  Future<void> updateWidgetSettings(void Function(Settings s) apply) async {
    apply(settings);
    notifyListeners();
    await _syncWidget();
  }
}
