package fr.perfdeck.app;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

/**
 * Appels au PC hors de l'écran principal (alertes en arrière-plan, tuile, widget).
 * Essaie d'abord la dernière adresse qui a marché, puis la maison, puis Meshnet / Tailscale.
 */
final class Api {
    static final String K_LAST = "last", K_NATIVE = "native";

    private Api() { }

    static SharedPreferences prefs(Context c) { return c.getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE); }

    static boolean ready(Context c) { return !prefs(c).getString(MainActivity.K_TOKEN, "").isEmpty() && !bases(c).isEmpty(); }

    /** Réglages poussés par la télécommande : micro principal, alertes, boutons de volume. */
    static JSONObject nativeCfg(Context c) {
        try { return new JSONObject(prefs(c).getString(K_NATIVE, "{}")); } catch (Exception e) { return new JSONObject(); }
    }

    static List<String> bases(Context c) {
        SharedPreferences p = prefs(c);
        List<String> out = new ArrayList<String>();
        String last = p.getString(K_LAST, "");
        if (!last.isEmpty()) out.add(last);
        for (String k : new String[]{MainActivity.K_HOME, MainActivity.K_REMOTE}) {
            try {
                JSONArray a = new JSONArray(p.getString(k, "[]"));
                for (int i = 0; i < a.length(); i++) {
                    String b = a.optString(i);
                    if (!b.isEmpty() && !out.contains(b)) out.add(b);
                }
            } catch (Exception ignored) { }
        }
        return out;
    }

    /** Réponse JSON du PC (avec « _code »), ou null si aucune adresse ne répond. */
    static JSONObject call(Context c, String path, String postJson, int timeout) {
        String token = prefs(c).getString(MainActivity.K_TOKEN, "");
        for (String b : bases(c)) {
            JSONObject r = once(b + path, token, postJson, timeout);
            if (r != null) {
                if (!b.equals(prefs(c).getString(K_LAST, ""))) prefs(c).edit().putString(K_LAST, b).apply();
                return r;
            }
        }
        return null;
    }

    private static JSONObject once(String url, String token, String postJson, int timeout) {
        HttpURLConnection h = null;
        try {
            h = (HttpURLConnection) new URL(url).openConnection();
            h.setConnectTimeout(timeout);
            h.setReadTimeout(timeout + 6000);
            h.setRequestProperty("X-Token", token);
            if (postJson != null) {
                h.setRequestMethod("POST");
                h.setDoOutput(true);
                h.setRequestProperty("Content-Type", "application/json");
                OutputStream o = h.getOutputStream();
                o.write(postJson.getBytes("UTF-8"));
                o.close();
            }
            int code = h.getResponseCode();
            InputStream in = code < 400 ? h.getInputStream() : h.getErrorStream();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            if (in != null) {
                byte[] b = new byte[4096];
                int n;
                while ((n = in.read(b)) > 0) buf.write(b, 0, n);
            }
            String s = buf.toString("UTF-8").trim();
            JSONObject j = s.startsWith("{") ? new JSONObject(s) : new JSONObject();
            j.put("_code", code);
            return j;
        } catch (Exception e) {
            return null;
        } finally {
            if (h != null) h.disconnect();
        }
    }

    /** Micro muet / actif, ou seulement son état (toggle = false). */
    static JSONObject mic(Context c, boolean toggle) {
        JSONObject body = new JSONObject();
        try {
            body.put("action", toggle ? "mic" : "micstate");
            body.put("mic", nativeCfg(c).optString("mic", ""));
        } catch (Exception ignored) { }
        return call(c, "/api/obs-action", body.toString(), 2500);
    }

    static JSONObject clip(Context c) {
        return call(c, "/api/obs-action", "{\"action\":\"clip\"}", 2500);
    }
}
