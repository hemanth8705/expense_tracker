package com.fersonal.expense_tracker

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Renders the values the Flutter side pre-computed and saved through home_widget. */
class ExpenseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.expense_widget).apply {
                setTextViewText(R.id.w_title, widgetData.getString("w_title", "Expenses"))
                setTextViewText(R.id.w_subtitle, widgetData.getString("w_subtitle", "Open the app to refresh"))
                setTextViewText(R.id.w_debit, widgetData.getString("w_debit", "-"))
                setTextViewText(R.id.w_credit, widgetData.getString("w_credit", "-"))
                setTextViewText(R.id.w_net, widgetData.getString("w_net", "-"))
                setViewVisibility(R.id.row_debit, vis(widgetData.getBoolean("w_show_debit", true)))
                setViewVisibility(R.id.row_credit, vis(widgetData.getBoolean("w_show_credit", true)))
                setViewVisibility(R.id.row_net, vis(widgetData.getBoolean("w_show_net", true)))
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun vis(show: Boolean) = if (show) View.VISIBLE else View.GONE
}
