package fr.perfdeck.app;

import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import org.json.JSONObject;

/** Tuile « Micro » des réglages rapides : coupe ou rouvre le micro OBS sans ouvrir l'appli. */
public class MicTileService extends TileService {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private volatile boolean busy;

    @Override
    public void onStartListening() { work(false); }

    @Override
    public void onClick() {
        if (!Api.ready(this)) { openApp(); return; }
        if (busy) return;
        show(Tile.STATE_ACTIVE, "Micro…");
        work(true);
    }

    private void work(final boolean toggle) {
        busy = true;
        new Thread(new Runnable() {
            public void run() {
                JSONObject r = Api.ready(MicTileService.this) ? Api.mic(MicTileService.this, toggle) : null;
                busy = false;
                if (r == null) show(Tile.STATE_UNAVAILABLE, "Micro (PC injoignable)");
                else if (!r.optBoolean("ok")) show(Tile.STATE_UNAVAILABLE, "Micro (OBS fermé)");
                else if (r.optBoolean("muted")) show(Tile.STATE_INACTIVE, "Micro coupé");
                else show(Tile.STATE_ACTIVE, "Micro actif");
            }
        }).start();
    }

    // Android 14+ n'accepte plus qu'un PendingIntent ; appelé par réflexion (compilé avec l'API 23)
    private void openApp() {
        Intent i = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                PendingIntent pi = PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
                TileService.class.getMethod("startActivityAndCollapse", PendingIntent.class).invoke(this, pi);
            } else {
                startActivityAndCollapse(i);
            }
        } catch (Exception e) {
            try { startActivity(i); } catch (Exception ignored) { }
        }
    }

    private void show(final int state, final String label) {
        ui.post(new Runnable() {
            public void run() {
                Tile t = getQsTile();
                if (t == null) return;
                t.setState(state);
                t.setLabel(label);
                t.updateTile();
            }
        });
    }
}
