package fr.perfdeck.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Vibrator;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * PerfDeck pour Android.
 * Trouve le PC sur le Wi-Fi, s'associe avec le code à 6 chiffres affiché par PerfManager,
 * puis affiche la télécommande. À la maison il passe par le Wi-Fi, ailleurs par Meshnet / Tailscale.
 */
public class MainActivity extends Activity {
    static final String PREFS = "perfdeck";
    static final String K_HOME = "home", K_REMOTE = "remote", K_TOKEN = "token", K_PC = "pc", K_WEB = "websettings";
    static final int PORT = 8765;
    static final int BG = 0xFF0D0D12, PANEL = 0xFF17171F, PANEL2 = 0xFF22222D, LINE = 0xFF2A2A37,
            TEXT = 0xFFECECF2, DIM = 0xFF8B8B9E, ACCENT = 0xFF7C5CFF;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService bg = Executors.newCachedThreadPool();
    private FrameLayout root;
    private WebView web;
    private String base;
    private boolean remoteMode;
    private int webErrors;
    private volatile int connectGen, discoverGen;

    // ================================================================== Cycle de vie
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        root = new FrameLayout(this);
        root.setBackgroundColor(BG);
        setContentView(root);
        if (configured()) connect(); else showSetup();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Revenu à la maison alors qu'on passait par Meshnet : on repasse sur le Wi-Fi (plus rapide)
        if (web != null && remoteMode && !list(K_HOME).isEmpty()) {
            final int gen = connectGen;
            bg.execute(new Runnable() {
                public void run() {
                    for (final String b : list(K_HOME)) {
                        if (ping(b, token(), 1200) == 200) {
                            ui.post(new Runnable() { public void run() { if (gen == connectGen) showWeb(b, false); } });
                            return;
                        }
                    }
                }
            });
        }
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        bg.shutdownNow();
        super.onDestroy();
    }

    // ================================================================== Réglages
    private SharedPreferences prefs() { return getSharedPreferences(PREFS, MODE_PRIVATE); }
    private String token() { return prefs().getString(K_TOKEN, ""); }
    private boolean configured() { return !token().isEmpty() && (!list(K_HOME).isEmpty() || !list(K_REMOTE).isEmpty()); }

    private List<String> list(String key) {
        List<String> out = new ArrayList<String>();
        try {
            JSONArray a = new JSONArray(prefs().getString(key, "[]"));
            for (int i = 0; i < a.length(); i++) if (!a.optString(i).isEmpty()) out.add(a.optString(i));
        } catch (Exception ignored) { }
        return out;
    }

    private void save(String token, JSONArray home, JSONArray remote, String pc) {
        prefs().edit()
                .putString(K_TOKEN, token)
                .putString(K_HOME, home == null ? "[]" : home.toString())
                .putString(K_REMOTE, remote == null ? "[]" : remote.toString())
                .putString(K_PC, pc == null ? "" : pc)
                .apply();
    }

    private static boolean isMeshAddress(String host) {
        // Meshnet NordVPN et Tailscale utilisent 100.64.0.0/10
        try {
            String[] p = host.split("\\.");
            if (p.length != 4) return host.endsWith(".nord") || host.endsWith(".ts.net");
            int a = Integer.parseInt(p[0]), b = Integer.parseInt(p[1]);
            return a == 100 && b >= 64 && b <= 127;
        } catch (Exception e) { return false; }
    }

    // ================================================================== Réseau
    private static String read(InputStream in) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        return out.toString("UTF-8");
    }

    /** Code HTTP de /api/status avec le code d'accès, ou -1 si le PC ne répond pas. */
    private static int ping(String b, String token, int timeout) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(b + "/api/status").openConnection();
            c.setConnectTimeout(timeout);
            c.setReadTimeout(timeout + 2000);
            c.setRequestProperty("X-Token", token);
            return c.getResponseCode();
        } catch (Exception e) {
            return -1;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    private static JSONObject http(String url, String postJson, int timeout) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(timeout);
            c.setReadTimeout(timeout + 3000);
            if (postJson != null) {
                c.setRequestMethod("POST");
                c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/json");
                OutputStream o = c.getOutputStream();
                o.write(postJson.getBytes("UTF-8"));
                o.close();
            }
            int code = c.getResponseCode();
            InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream();
            JSONObject j = new JSONObject(in == null ? "{}" : read(in));
            j.put("_code", code);
            return j;
        } catch (Exception e) {
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    /** Préfixes des réseaux locaux du téléphone (ex. « 192.168.1. »), Wi-Fi d'abord. */
    private static List<String> localPrefixes() {
        List<String> wifi = new ArrayList<String>(), other = new ArrayList<String>();
        try {
            Enumeration<NetworkInterface> it = NetworkInterface.getNetworkInterfaces();
            while (it != null && it.hasMoreElements()) {
                NetworkInterface ni = it.nextElement();
                if (!ni.isUp() || ni.isLoopback()) continue;
                Enumeration<InetAddress> addrs = ni.getInetAddresses();
                while (addrs.hasMoreElements()) {
                    InetAddress a = addrs.nextElement();
                    if (!(a instanceof Inet4Address) || !a.isSiteLocalAddress()) continue;
                    String ip = a.getHostAddress();
                    String prefix = ip.substring(0, ip.lastIndexOf('.') + 1);
                    String name = ni.getName().toLowerCase();
                    List<String> target = (name.startsWith("wlan") || name.startsWith("eth") || name.startsWith("ap")) ? wifi : other;
                    if (!wifi.contains(prefix) && !other.contains(prefix)) target.add(prefix);
                }
            }
        } catch (Exception ignored) { }
        List<String> out = new ArrayList<String>(wifi);
        if (out.isEmpty()) out.addAll(other);
        return out;
    }

    // ================================================================== Interface : petits outils
    private int dp(float v) { return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()); }

    private TextView text(String s, float sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setLineSpacing(0, 1.15f);
        return t;
    }

    private GradientDrawable rounded(int color, int radius, int stroke) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(radius);
        if (stroke != 0) d.setStroke(dp(1), stroke);
        return d;
    }

    private Button button(String label, boolean primary) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTextColor(0xFFFFFFFF);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setBackground(rounded(primary ? ACCENT : PANEL2, dp(14), 0));
        b.setStateListAnimator(null);
        return b;
    }

    private LinearLayout.LayoutParams wide(int height, int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height);
        lp.topMargin = top;
        return lp;
    }

    private LinearLayout page() {
        root.removeAllViews();
        if (web != null) { web.destroy(); web = null; }
        base = null;
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER_VERTICAL);
        box.setPadding(dp(24), dp(36), dp(24), dp(36));
        scroll.addView(box, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(scroll);
        return box;
    }

    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_LONG).show(); }

    // ================================================================== Association avec le PC
    private void showSetup() {
        connectGen++;
        LinearLayout box = page();
        box.addView(text("PerfDeck", 34, TEXT, true));
        TextView sub = text("Télécommande OBS et PerfManager", 15, DIM, false);
        sub.setPadding(0, dp(4), 0, dp(24));
        box.addView(sub);

        final TextView status = text("Recherche du PC sur le Wi-Fi…", 15, TEXT, false);
        box.addView(status);
        final LinearLayout found = new LinearLayout(this);
        found.setOrientation(LinearLayout.VERTICAL);
        box.addView(found, wide(ViewGroup.LayoutParams.WRAP_CONTENT, dp(12)));

        Button again = button("Rechercher à nouveau", false);
        again.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { discover(status, found); }
        });
        box.addView(again, wide(dp(50), dp(12)));

        TextView hint = text("Sur le PC : clic droit sur l'icône PerfManager → « Connecter le téléphone » affiche le code à 6 chiffres. "
                + "Le téléphone doit être sur le même Wi-Fi que le PC pour la première connexion.", 13, DIM, false);
        hint.setPadding(0, dp(16), 0, 0);
        box.addView(hint);

        TextView or = text("Ou colle l'adresse complète affichée par le PC :", 13, DIM, false);
        or.setPadding(0, dp(28), 0, dp(8));
        box.addView(or);
        final EditText input = new EditText(this);
        input.setHint("http://192.168.1.20:8765/?k=…");
        input.setHintTextColor(0xFF55556A);
        input.setTextColor(TEXT);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setImeOptions(EditorInfo.IME_ACTION_GO);
        input.setPadding(dp(16), dp(14), dp(16), dp(14));
        input.setBackground(rounded(PANEL, dp(14), LINE));
        box.addView(input, wide(ViewGroup.LayoutParams.WRAP_CONTENT, 0));
        Button go = button("Se connecter avec l'adresse", false);
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { manual(input.getText().toString()); }
        });
        input.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            public boolean onEditorAction(TextView v, int id, KeyEvent e) { manual(input.getText().toString()); return true; }
        });
        box.addView(go, wide(dp(50), dp(10)));

        discover(status, found);
    }

    private void discover(final TextView status, final LinearLayout found) {
        final int gen = ++discoverGen;
        status.setText("Recherche du PC sur le Wi-Fi…");
        found.removeAllViews();
        bg.execute(new Runnable() {
            public void run() {
                List<String> prefixes = localPrefixes();
                if (prefixes.isEmpty()) {
                    post(gen, new Runnable() { public void run() {
                        status.setText("Pas de Wi-Fi : connecte le téléphone au Wi-Fi du PC, ou colle l'adresse ci-dessous.");
                    } });
                    return;
                }
                final Set<String> seen = Collections.synchronizedSet(new HashSet<String>());
                ExecutorService pool = Executors.newFixedThreadPool(48);
                for (String prefix : prefixes) {
                    for (int i = 1; i < 255; i++) {
                        final String host = prefix + i;
                        pool.execute(new Runnable() {
                            public void run() {
                                if (gen != discoverGen) return;
                                final JSONObject h = http("http://" + host + ":" + PORT + "/api/hello", null, 700);
                                if (h == null || !"perfdeck".equals(h.optString("app")) || !seen.add(host)) return;
                                post(gen, new Runnable() { public void run() { addPc(found, status, host, h.optString("pc", "PC")); } });
                            }
                        });
                    }
                }
                pool.shutdown();
                try { pool.awaitTermination(20, TimeUnit.SECONDS); } catch (InterruptedException ignored) { }
                post(gen, new Runnable() { public void run() {
                    status.setText(seen.isEmpty()
                            ? "Aucun PC trouvé. Vérifie que PerfManager tourne sur le PC et que le téléphone est sur le même Wi-Fi."
                            : "Touche ton PC pour l'associer :");
                } });
            }
        });
    }

    private void post(final int gen, final Runnable r) {
        ui.post(new Runnable() { public void run() { if (gen == discoverGen && web == null) r.run(); } });
    }

    private void addPc(LinearLayout found, TextView status, final String host, final String name) {
        status.setText("Touche ton PC pour l'associer :");
        Button b = button(name + "   ·   " + host, true);
        b.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        b.setPadding(dp(18), 0, dp(18), 0);
        b.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { askPin(host, name); }
        });
        found.addView(b, wide(dp(58), dp(8)));
    }

    private void askPin(final String host, final String name) {
        final EditText pin = new EditText(this);
        pin.setInputType(InputType.TYPE_CLASS_NUMBER);
        pin.setHint("123456");
        pin.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        pin.setGravity(Gravity.CENTER);
        FrameLayout wrap = new FrameLayout(this);
        wrap.setPadding(dp(24), dp(8), dp(24), 0);
        wrap.addView(pin);
        new AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle("Code affiché sur " + name)
                .setMessage("Sur le PC : clic droit sur l'icône PerfManager → « Connecter le téléphone ».")
                .setView(wrap)
                .setPositiveButton("Associer", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) { pair(host, pin.getText().toString().trim()); }
                })
                .setNegativeButton("Annuler", null)
                .show();
    }

    private void pair(final String host, final String pin) {
        toast("Association…");
        bg.execute(new Runnable() {
            public void run() {
                JSONObject body = new JSONObject();
                try { body.put("pin", pin); } catch (Exception ignored) { }
                final JSONObject r = http("http://" + host + ":" + PORT + "/api/pair", body.toString(), 3000);
                ui.post(new Runnable() {
                    public void run() {
                        if (r == null) { toast("Le PC ne répond pas"); return; }
                        if (r.optInt("_code") != 200 || r.optString("token").isEmpty()) {
                            toast(r.optString("error", "Code incorrect"));
                            return;
                        }
                        JSONArray home = r.optJSONArray("home");
                        if (home == null || home.length() == 0) { home = new JSONArray(); home.put("http://" + host + ":" + PORT); }
                        JSONArray remote = r.optJSONArray("remote");
                        save(r.optString("token"), home, remote, r.optString("pc"));
                        toast(remote != null && remote.length() > 0
                                ? "Associé ! Marche aussi hors de chez toi via Meshnet / Tailscale."
                                : "Associé ! Active Meshnet ou Tailscale sur le PC pour l'utiliser hors de chez toi.");
                        connect();
                    }
                });
            }
        });
    }

    private void manual(String raw) {
        String s = raw == null ? "" : raw.trim();
        if (s.isEmpty()) { toast("Colle l'adresse affichée par le PC"); return; }
        if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://" + s;
        Uri u = Uri.parse(s);
        String k = u.getQueryParameter("k");
        if (u.getHost() == null || k == null || k.isEmpty()) {
            toast("Il manque le code d'accès (?k=…) : copie l'adresse complète affichée par le PC");
            return;
        }
        String b = u.getScheme() + "://" + u.getHost() + ":" + (u.getPort() > 0 ? u.getPort() : PORT);
        JSONArray one = new JSONArray();
        one.put(b);
        if (isMeshAddress(u.getHost())) save(k, null, one, null); else save(k, one, null, null);
        connect();
    }

    // ================================================================== Connexion : maison d'abord, puis Meshnet
    private void showLoading(String msg) {
        LinearLayout box = page();
        box.setGravity(Gravity.CENTER);
        box.addView(new ProgressBar(this));
        TextView t = text(msg, 16, DIM, false);
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, dp(16), 0, 0);
        box.addView(t);
    }

    private void connect() {
        final int gen = ++connectGen;
        String pc = prefs().getString(K_PC, "");
        showLoading("Connexion à " + (pc.isEmpty() ? "ton PC" : pc) + "…");
        final List<String> home = list(K_HOME), remote = list(K_REMOTE);
        final String tok = token();
        bg.execute(new Runnable() {
            public void run() {
                boolean denied = false;
                for (String b : home) {
                    int c = ping(b, tok, 1500);
                    if (c == 200) { go(gen, b, false); return; }
                    if (c == 401) denied = true;
                }
                for (String b : remote) {
                    int c = ping(b, tok, 5000);
                    if (c == 200) { go(gen, b, true); return; }
                    if (c == 401) denied = true;
                }
                final boolean wasDenied = denied;
                ui.post(new Runnable() {
                    public void run() {
                        if (gen != connectGen) return;
                        if (wasDenied) showError("Code d'accès refusé", "Le PC a changé de code d'accès : associe le téléphone à nouveau.");
                        else showError("PC injoignable", remote.isEmpty()
                                ? "Vérifie que PerfManager tourne sur le PC et que le téléphone est sur le même Wi-Fi.\n\nPour l'utiliser hors de chez toi, active NordVPN Meshnet (ou Tailscale) sur le PC puis associe à nouveau le téléphone."
                                : "Le PC ne répond ni à la maison ni via Meshnet / Tailscale. Est-il allumé, avec PerfManager et Meshnet actifs ?");
                    }
                });
            }
        });
    }

    private void go(final int gen, final String b, final boolean remote) {
        ui.post(new Runnable() { public void run() { if (gen == connectGen) showWeb(b, remote); } });
    }

    private void showError(String title, String detail) {
        LinearLayout box = page();
        box.setGravity(Gravity.CENTER);
        TextView t = text(title, 24, TEXT, true);
        t.setGravity(Gravity.CENTER);
        box.addView(t);
        TextView d = text(detail, 15, DIM, false);
        d.setGravity(Gravity.CENTER);
        d.setPadding(0, dp(10), 0, dp(24));
        box.addView(d);
        Button retry = button("Réessayer", true);
        retry.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { connect(); } });
        box.addView(retry, wide(dp(52), 0));
        Button change = button("Associer à nouveau", false);
        change.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { showSetup(); } });
        box.addView(change, wide(dp(52), dp(10)));
    }

    // ================================================================== Télécommande
    private void showWeb(String b, boolean remote) {
        if (web != null && b.equals(base)) return;
        root.removeAllViews();
        if (web != null) web.destroy();
        base = b;
        remoteMode = remote;
        webErrors = 0;

        web = new WebView(this);
        web.setBackgroundColor(BG);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUserAgentString(s.getUserAgentString() + " PerfDeckApp");
        web.addJavascriptInterface(new Bridge(), "PerfDeckNative");
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            // API 24+ (pas d'@Override : on compile avec android-23, le système l'appelle quand même)
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri target = req.getUrl();
                if (base != null && target.getHost() != null && target.getHost().equals(Uri.parse(base).getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, target)); } catch (Exception ignored) { }
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError err) {
                if (!req.isForMainFrame()) return;
                // Changement de réseau (sortie de la maison…) : on recherche le PC par l'autre chemin
                if (++webErrors <= 1) connect();
                else showError("PC injoignable", String.valueOf(err.getDescription()));
            }
        });
        root.addView(web, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        try {
            web.loadUrl(b + "/?k=" + URLEncoder.encode(token(), "UTF-8"));
        } catch (Exception e) {
            web.loadUrl(b + "/");
        }
        Toast.makeText(this, remote ? "Connecté via Meshnet / Tailscale" : "Connecté via le Wi-Fi", Toast.LENGTH_SHORT).show();
    }

    @Override
    public void onBackPressed() {
        if (web == null) { super.onBackPressed(); return; }
        new AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle("PerfDeck")
                .setItems(new String[]{"Recharger", "Associer un autre PC", "Quitter"}, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int which) {
                        if (which == 0) connect();
                        else if (which == 1) showSetup();
                        else finish();
                    }
                })
                .show();
    }

    // ================================================================== Pont JavaScript ↔ Android
    private class Bridge {
        @JavascriptInterface
        public void vibrate(String json) {
            try {
                JSONArray a = new JSONArray(json);
                Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (v == null || a.length() == 0) return;
                long[] pattern = new long[a.length() + 1];
                pattern[0] = 0;
                for (int i = 0; i < a.length(); i++) pattern[i + 1] = Math.max(1, a.getLong(i));
                v.vibrate(pattern, -1);
            } catch (Exception ignored) { }
        }

        /** Réglages de la télécommande (mot de passe OBS, alertes) gardés par l'appli : identiques à la maison et via Meshnet. */
        @JavascriptInterface
        public String loadSettings() { return prefs().getString(K_WEB, ""); }

        @JavascriptInterface
        public void saveSettings(String json) { prefs().edit().putString(K_WEB, json == null ? "" : json).apply(); }

        @JavascriptInterface
        public void changeServer() { ui.post(new Runnable() { public void run() { showSetup(); } }); }

        @JavascriptInterface
        public String mode() { return remoteMode ? "distance" : "maison"; }

        @JavascriptInterface
        public String version() {
            try { return getPackageManager().getPackageInfo(getPackageName(), 0).versionName; }
            catch (Exception e) { return ""; }
        }
    }
}
