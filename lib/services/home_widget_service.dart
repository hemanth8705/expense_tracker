import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/format.dart';
import '../models/models.dart';
import 'repository.dart';
import 'settings.dart';

/// Computes the figures for the home-screen widget and pushes them to the
/// native AppWidgetProvider (ExpenseWidgetProvider.kt).
class HomeWidgetService {
  static const _provider = 'com.fersonal.expense_tracker.ExpenseWidgetProvider';

  /// Never throws and never blocks the caller for more than a few seconds.
  static Future<void> update(Repository repo, Settings s, List<Tag> tags) async {
    try {
      await _update(repo, s, tags).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Widget update skipped: $e');
    }
  }

  static Future<void> _update(Repository repo, Settings s, List<Tag> tags) async {
    {
      final period = s.resolveWidgetPeriod(DateTime.now());
      final tagId = s.widgetTagId;
      final filter = TxnFilter(
        start: period.start,
        end: period.end,
        untaggedOnly: tagId == -1,
        tagId: (tagId == null || tagId == -1) ? null : tagId,
      );
      final t = await repo.totals(filter);

      String scope;
      if (tagId == null) {
        scope = 'All transactions';
      } else if (tagId == -1) {
        scope = 'No tag';
      } else {
        scope = tags.where((x) => x.id == tagId).firstOrNull?.name ?? 'All transactions';
      }

      await Future.wait([
        HomeWidget.saveWidgetData<String>('w_title', period.label),
        HomeWidget.saveWidgetData<String>('w_subtitle', '$scope · ${t.count} txns'),
        HomeWidget.saveWidgetData<String>('w_debit', money(t.debit)),
        HomeWidget.saveWidgetData<String>('w_credit', money(t.credit)),
        HomeWidget.saveWidgetData<String>('w_net', money(t.net, signed: true)),
        HomeWidget.saveWidgetData<bool>('w_show_debit', s.widgetShowDebit),
        HomeWidget.saveWidgetData<bool>('w_show_credit', s.widgetShowCredit),
        HomeWidget.saveWidgetData<bool>('w_show_net', s.widgetShowNet),
      ]);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    }
  }

  static Future<bool> canPin() async {
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> pin() => HomeWidget.requestPinWidget(qualifiedAndroidName: _provider);
}
