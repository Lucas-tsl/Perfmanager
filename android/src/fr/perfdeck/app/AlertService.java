package fr.perfdeck.app;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.URLEncoder;
import java.util.HashMap;
import java.util.Map;

/**
 * Alertes du live même écran éteint : interroge le PC toutes les 5 s (/api/alerts) et envoie
 * une vraie notification Android (images perdues, micro coupé, GPU chaud, OBS planté, PC injoignable).
 * Tant que PerfDeck est à l'écran, c'est la télécommande qui affiche les alertes.
 */
public class AlertService extends Service {
    static final String CH_BG = "perfdeck_watch", CH_ALERT = "perfdeck_alerts";
    static final int ID_FG = 1;
    static final long REPEAT_MS = 3 * 60 * 1000;

    private volatile boolean running;
    private Thread loop;
    private PowerManager.WakeLock wake;
    private final Map<String, Long> shown = new HashMap<String, Long>();

    static void sync(Context c) {
        boolean on = Api.nativeCfg(c).optBoolean("bg", false) && Api.ready(c);
        Intent i = new Intent(c, AlertService.class);
        try {
            if (on) c.startService(i); else c.stopService(i);
        } catch (Exception ignored) { }
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onCreate() {
        super.onCreate();
        channels(this);
        startForeground(ID_FG, build(this, CH_BG, "PerfDeck surveille ton live", "Alertes actives même écran éteint", false, Notification.PRIORITY_MIN));
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "perfdeck:alerts");
            wake.setReferenceCounted(false);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!running) {
            running = true;
            loop = new Thread(new Runnable() { public void run() { poll(); } }, "perfdeck-alerts");
            loop.start();
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (loop != null) loop.interrupt();
        if (wake != null && wake.isHeld()) wake.release();
        super.onDestroy();
    }

    private void poll() {
        int fails = 0;
        boolean wasLive = false;
        while (running) {
            JSONObject cfg = Api.nativeCfg(this);
            if (!cfg.optBoolean("bg", false)) { stopSelf(); return; }
            JSONObject a = cfg.optJSONObject("alerts");
            if (a == null) a = new JSONObject();
            try { if (wake != null) wake.acquire(15000); } catch (Exception ignored) { }
            JSONObject r = Api.call(this, "/api/alerts" + query(a, cfg.optString("mic", "")), null, 4000);
            if (r == null || r.optInt("_code") != 200) {
                fails++;
                if (fails == 3 && wasLive && a.optBoolean("link", true)) notifyAlert("link", "bad", "Le PC ne répond plus pendant le live", a);
            } else {
                if (fails >= 3 && wasLive) notifyAlert("link-ok", "ok", "Le PC répond de nouveau", a);
                fails = 0;
                wasLive = r.optBoolean("live", false);
                JSONArray list = r.optJSONArray("alerts");
                for (int i = 0; list != null && i < list.length(); i++) {
                    JSONObject al = list.optJSONObject(i);
                    if (al != null) notifyAlert(al.optString("key"), al.optString("level"), al.optString("msg"), a);
                }
            }
            try { if (wake != null && wake.isHeld()) wake.release(); } catch (Exception ignored) { }
            try { Thread.sleep(5000); } catch (InterruptedException e) { return; }
        }
    }

    private static String query(JSONObject a, String mic) {
        StringBuilder q = new StringBuilder("?drop=").append(a.optDouble("dropPct", 1))
                .append("&gpu=").append(a.optDouble("gpuTemp", 80))
                .append("&cpu=").append(a.optDouble("cpuPct", 90))
                .append("&micsec=").append(a.optDouble("micSec", 30))
                .append("&l=").append(a.optBoolean("link", true) ? 1 : 0)
                .append("&d=").append(a.optBoolean("drop", true) ? 1 : 0)
                .append("&g=").append(a.optBoolean("gpu", true) ? 1 : 0)
                .append("&c=").append(a.optBoolean("cpu", true) ? 1 : 0)
                .append("&m=").append(a.optBoolean("mic", true) ? 1 : 0);
        try { if (!mic.isEmpty()) q.append("&micname=").append(URLEncoder.encode(mic, "UTF-8")); } catch (Exception ignored) { }
        return q.toString();
    }

    private void notifyAlert(String key, String level, String msg, JSONObject a) {
        if (MainActivity.visible || msg == null || msg.isEmpty()) return;
        long now = System.currentTimeMillis();
        Long last = shown.get(key);
        if (last != null && now - last < REPEAT_MS) return;
        shown.put(key, now);
        String title = "ok".equals(level) ? "PerfDeck" : "bad".equals(level) ? "⚠ Problème sur le live" : "PerfDeck : attention";
        Notification n = build(this, CH_ALERT, title, msg, a.optBoolean("vibrate", true), Notification.PRIORITY_HIGH);
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(100 + (key.hashCode() & 0xffff), n);
    }

    // ------------------------------------------------------------ Notifications (canaux Android 8+ par réflexion : compilé avec l'API 23)
    static void channels(Context c) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        try {
            Class<?> ch = Class.forName("android.app.NotificationChannel");
            Object bg = ch.getConstructor(String.class, CharSequence.class, int.class).newInstance(CH_BG, "Surveillance du live", 1 /* MIN */);
            Object al = ch.getConstructor(String.class, CharSequence.class, int.class).newInstance(CH_ALERT, "Alertes du live", 4 /* HIGH */);
            ch.getMethod("enableVibration", boolean.class).invoke(al, true);
            NotificationManager.class.getMethod("createNotificationChannel", ch).invoke(nm, bg);
            NotificationManager.class.getMethod("createNotificationChannel", ch).invoke(nm, al);
        } catch (Exception ignored) { }
    }

    static Notification build(Context c, String channel, String title, String text, boolean vibrate, int priority) {
        Intent open = new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder b = new Notification.Builder(c)
                .setSmallIcon(R.drawable.ic_stat)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setColor(MainActivity.ACCENT)
                .setContentIntent(pi)
                .setPriority(priority)
                .setAutoCancel(!CH_BG.equals(channel))
                .setOngoing(CH_BG.equals(channel));
        if (vibrate) b.setVibrate(new long[]{0, 250, 120, 250});
        if (Build.VERSION.SDK_INT >= 26) {
            try { Notification.Builder.class.getMethod("setChannelId", String.class).invoke(b, channel); } catch (Exception ignored) { }
        }
        return b.build();
    }
}
