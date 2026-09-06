package io.getflash.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The 1x1 home screen widget: the unread count, and a tap that opens Flash.
 *
 * The number is pushed from Dart, never computed here. `UnreadBadgeService`
 * already owns "the unread total right now" and writes it to home_widget's
 * shared prefs on the same call that sets the launcher badge, so the widget
 * and the badge cannot disagree — there is no second count to drift.
 *
 * Nothing here reads the theme. The background drawable and the text colour
 * are both resource references with `-night` variants, resolved when the
 * launcher inflates the RemoteViews. Branching on `uiMode` in this class was
 * the alternative, and it would have read the *app* process's configuration
 * while the drawable resolved against the *launcher's* — normally the same,
 * but able to disagree under a per-app dark mode, which is exactly the state
 * where a half-dark widget would look broken.
 */
class UnreadWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // 0 when absent, which is the state on a fresh placement before the
        // app has ever run: an empty widget or a crash would both be worse
        // than an honest zero.
        val count = widgetData.getInt(KEY_COUNT, 0)
        val label = if (count > MAX_SHOWN) "$MAX_SHOWN+" else count.toString()

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_unread)
            views.setTextViewText(R.id.widget_unread_count, label)
            views.setOnClickPendingIntent(R.id.widget_unread_root, launchIntent(context))
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /**
     * The launcher entry the manifest already declares, rather than a new
     * intent shape — so tapping the widget lands exactly where tapping the
     * icon does, including `singleTop` reusing a running task instead of
     * stacking a second copy of MainActivity.
     */
    private fun launchIntent(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        /** Must match `UnreadWidgetService._dataKey`. */
        const val KEY_COUNT = "unread_count"

        /**
         * Above this the widget reads "99+". Same cutoff as `kMaxBadgeCount`,
         * which the launcher badge already caps at — but this one can render
         * the plus, because it is a TextView we draw rather than an int handed
         * to the OS.
         */
        const val MAX_SHOWN = 99
    }
}
