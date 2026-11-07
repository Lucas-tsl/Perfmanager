package fr.perfdeck.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
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
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.google.zxing.integration.android.IntentIntegrator;
import com.google.zxing.integration.android.IntentResult;

import org.json.JSONArray;

/**
 * PerfDeck pour Android : affiche la télécommande servie par PerfRemote sur le PC,
 * garde l'écran allumé et fait vibrer le téléphone pour les alertes.
 */
public class MainActivity extends Activity {
    private static final String PREFS = "perfdeck";
    private static final String KEY_URL = "url";
    private static final int BG = 0xFF0D0D12, PANEL = 0xFF17171F, TEXT = 0xFFECECF2, DIM = 0xFF8B8B9E, ACCENT = 0xFF7C5CFF;

    private FrameLayout root;
    private WebView web;
    private View errorView;
    private String currentUrl;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        root = new FrameLayout(this);
        root.setBackgroundColor(BG);
        setContentView(root);

        String url = prefs().getString(KEY_URL, null);
        if (url == null) showSetup(null);
        else showWeb(url);
    }

    private SharedPreferences prefs() { return getSharedPreferences(PREFS, MODE_PRIVATE); }

    private int dp(float v) { return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()); }

    // ------------------------------------------------------------------ Écran de connexion
    private void showSetup(String prefill) {
        root.removeAllViews();
        if (web != null) { web.destroy(); web = null; }
        errorView = null;

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER_VERTICAL);
        box.setPadding(dp(24), dp(40), dp(24), dp(40));
        scroll.addView(box, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        TextView title = text("PerfDeck", 34, TEXT, true);
        box.addView(title);
        TextView sub = text("Télécommande OBS et PerfManager", 15, DIM, false);
        sub.setPadding(0, dp(4), 0, dp(28));
        box.addView(sub);

        TextView step = text("Sur le PC, lance PerfManager puis « Connecter le téléphone » : un QR code s'affiche. "
                + "Le téléphone doit être sur le même Wi-Fi, ou connecté à Tailscale.", 15, TEXT, false);
        step.setPadding(0, 0, 0, dp(20));
        box.addView(step);

        Button scan = button("Scanner le QR code du PC", true);
        scan.setOnClickListener(v -> startScan());
        box.addView(scan, fullWidth(dp(56)));

        TextView or = text("ou saisis l'adresse affichée sous le QR code", 13, DIM, false);
        or.setGravity(Gravity.CENTER);
        or.setPadding(0, dp(24), 0, dp(10));
        box.addView(or);

        final EditText input = new EditText(this);
        input.setHint("http://192.168.1.20:8765/?k=…");
        input.setHintTextColor(0xFF55556A);
        input.setTextColor(TEXT);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setImeOptions(EditorInfo.IME_ACTION_GO);
        input.setPadding(dp(16), dp(14), dp(16), dp(14));
        input.setBackground(rounded(PANEL, dp(14), 0xFF2A2A37));
        if (prefill != null) input.setText(prefill);
        box.addView(input, fullWidth(ViewGroup.LayoutParams.WRAP_CONTENT));

        Button go = button("Se connecter", false);
        go.setOnClickListener(v -> connect(input.getText().toString()));
        input.setOnEditorActionListener((v, actionId, e) -> { connect(input.getText().toString()); return true; });
        LinearLayout.LayoutParams lp = fullWidth(dp(52));
        lp.topMargin = dp(12);
        box.addView(go, lp);

        root.addView(scroll);
    }

    private TextView text(String s, float sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setLineSpacing(0, 1.15f);
        return t;
    }

    private Button button(String label, boolean primary) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTextColor(0xFFFFFFFF);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setBackground(rounded(primary ? ACCENT : 0xFF22222D, dp(14), 0));
        b.setStateListAnimator(null);
        return b;
    }

    private GradientDrawable rounded(int color, int radius, int stroke) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(radius);
        if (stroke != 0) d.setStroke(dp(1), stroke);
        return d;
    }

    private LinearLayout.LayoutParams fullWidth(int height) {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height);
    }

    private void startScan() {
        IntentIntegrator integrator = new IntentIntegrator(this);
        integrator.setDesiredBarcodeFormats(IntentIntegrator.QR_CODE);
        integrator.setPrompt("Scanne le QR code affiché par PerfManager sur le PC");
        integrator.setBeepEnabled(false);
        integrator.setOrientationLocked(false);
        integrator.initiateScan();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        IntentResult r = IntentIntegrator.parseActivityResult(requestCode, resultCode, data);
        if (r != null) {
            if (r.getContents() != null) connect(r.getContents());
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private void connect(String raw) {
        String url = raw == null ? "" : raw.trim();
        if (url.isEmpty()) { toast("Saisis l'adresse du PC"); return; }
        if (!url.startsWith("http://") && !url.startsWith("https://")) url = "http://" + url;
        Uri u = Uri.parse(url);
        if (u.getHost() == null || u.getHost().isEmpty()) { toast("Adresse invalide"); return; }
        if (u.getPort() == -1 && "http".equals(u.getScheme())) url = url.replaceFirst(java.util.regex.Pattern.quote("://" + u.getHost()), "://" + u.getHost() + ":8765");
        prefs().edit().putString(KEY_URL, url).apply();
        showWeb(url);
    }

    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_SHORT).show(); }

    // ------------------------------------------------------------------ Télécommande
    private void showWeb(String url) {
        root.removeAllViews();
        errorView = null;
        currentUrl = url;

        web = new WebView(this);
        web.setBackgroundColor(BG);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUserAgentString(s.getUserAgentString() + " PerfDeckApp/" + BuildConfig.VERSION_NAME);
        web.addJavascriptInterface(new Bridge(), "PerfDeckNative");
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri target = req.getUrl();
                Uri home = Uri.parse(currentUrl);
                if (target.getHost() != null && target.getHost().equals(home.getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, target)); } catch (Exception ignored) { }
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError err) {
                if (req.isForMainFrame()) showError(String.valueOf(err.getDescription()));
            }

            @Override
            public void onPageFinished(WebView view, String u) {
                if (errorView != null && !u.startsWith("data:")) { root.removeView(errorView); errorView = null; }
            }
        });
        root.addView(web, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        web.loadUrl(url);
    }

    private void showError(String detail) {
        if (errorView != null) root.removeView(errorView);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setBackgroundColor(BG);
        box.setPadding(dp(28), dp(28), dp(28), dp(28));
        box.setClickable(true);

        box.addView(text("PC injoignable", 24, TEXT, true));
        TextView why = text("Vérifie que PerfManager tourne sur le PC et que le téléphone est sur le même Wi-Fi (ou que Tailscale est activé).\n\n" + detail, 15, DIM, false);
        why.setGravity(Gravity.CENTER);
        why.setPadding(0, dp(10), 0, dp(24));
        box.addView(why);

        Button retry = button("Réessayer", true);
        retry.setOnClickListener(v -> { if (web != null) web.loadUrl(currentUrl); });
        box.addView(retry, fullWidth(dp(52)));
        Button change = button("Changer de PC", false);
        change.setOnClickListener(v -> showSetup(currentUrl));
        LinearLayout.LayoutParams lp = fullWidth(dp(52));
        lp.topMargin = dp(10);
        box.addView(change, lp);

        errorView = box;
        root.addView(box, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }

    @Override
    public void onBackPressed() {
        if (web == null) { super.onBackPressed(); return; }
        new AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
                .setTitle("PerfDeck")
                .setItems(new String[]{"Recharger", "Changer de PC", "Quitter"}, (d, which) -> {
                    if (which == 0) web.loadUrl(currentUrl);
                    else if (which == 1) showSetup(currentUrl);
                    else finish();
                })
                .show();
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }

    // ------------------------------------------------------------------ Pont JavaScript ↔ Android
    private class Bridge {
        @JavascriptInterface
        public void vibrate(String json) {
            try {
                JSONArray a = new JSONArray(json);
                Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (v == null || a.length() == 0) return;
                if (a.length() == 1) { v.vibrate(VibrationEffect.createOneShot(Math.max(1, a.getLong(0)), VibrationEffect.DEFAULT_AMPLITUDE)); return; }
                long[] pattern = new long[a.length() + 1];
                pattern[0] = 0;
                for (int i = 0; i < a.length(); i++) pattern[i + 1] = a.getLong(i);
                v.vibrate(VibrationEffect.createWaveform(pattern, -1));
            } catch (Exception ignored) { }
        }

        @JavascriptInterface
        public void changeServer() { runOnUiThread(() -> showSetup(currentUrl)); }

        @JavascriptInterface
        public String version() { return BuildConfig.VERSION_NAME; }
    }
}
