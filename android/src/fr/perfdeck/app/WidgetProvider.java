package fr.perfdeck.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

import org.json.JSONObject;

/** Widget de l'écran d'accueil : micro muet / actif, clip, et ouverture de PerfDeck. */
public class WidgetProvider extends AppWidgetProvider {
    private static final String ACTION = "fr.perfdeck.app.WIDGET";

    @Override
    public void onUpdate(Context c, AppWidgetManager m, int[] ids) {
        render(c, null, -1);
        async(c, "state");
    }

    @Override
    public void onReceive(Context c, Intent i) {
        super.onReceive(c, i);
        if (ACTION.equals(i.getAction())) async(c, i.getStringExtra("what"));
    }

    private void async(final Context c, final String what) {
        final PendingResult pending = goAsync();
        new Thread(new Runnable() {
            public void run() {
                Context app = c.getApplicationContext();
                try {
                    if (!Api.ready(app)) { render(app, "Ouvre PerfDeck pour l'associer", -1); return; }
                    String msg = null;
                    if ("clip".equals(what)) {
                        render(app, "Clip…", -1);
                        JSONObject r = Api.clip(app);
                        msg = r == null ? "PC injoignable" : r.optString("message", r.optString("error", "Clip"));
                    }
                    JSONObject m = Api.mic(app, "mic".equals(what));
                    int muted = m == null || !m.optBoolean("ok") ? -1 : (m.optBoolean("muted") ? 1 : 0);
                    if (msg == null) msg = m == null ? "PC injoignable" : !m.optBoolean("ok") ? "OBS fermé"
                            : (muted == 1 ? "Micro coupé" : "Micro actif") + " · " + m.optString("mic");
                    render(app, msg, muted);
                } catch (Exception e) {
                    render(app, "PC injoignable", -1);
                } finally {
                    if (pending != null) pending.finish();
                }
            }
        }).start();
    }

    private static void render(Context c, String status, int muted) {
        RemoteViews v = new RemoteViews(c.getPackageName(), R.layout.widget);
        if (status != null) v.setTextViewText(R.id.status, status);
        if (muted >= 0) {
            v.setInt(R.id.mic, "setBackgroundResource", muted == 1 ? R.drawable.widget_btn_red : R.drawable.widget_btn_accent);
            v.setTextViewText(R.id.mic, muted == 1 ? "Micro\ncoupé" : "Micro");
        }
        v.setOnClickPendingIntent(R.id.mic, action(c, "mic"));
        v.setOnClickPendingIntent(R.id.clip, action(c, "clip"));
        v.setOnClickPendingIntent(R.id.info, action(c, "state"));
        v.setOnClickPendingIntent(R.id.open, PendingIntent.getActivity(c, 0, new Intent(c, MainActivity.class), PendingIntent.FLAG_IMMUTABLE));
        AppWidgetManager.getInstance(c).updateAppWidget(new ComponentName(c, WidgetProvider.class), v);
    }

    private static PendingIntent action(Context c, String what) {
        Intent i = new Intent(c, WidgetProvider.class).setAction(ACTION).putExtra("what", what);
        return PendingIntent.getBroadcast(c, what.hashCode(), i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
}
