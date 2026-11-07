package android.service.quicksettings;
// Talon de compilation (API 24) ; valeurs identiques à celles d'Android.
public final class Tile {
    public static final int STATE_UNAVAILABLE = 0;
    public static final int STATE_INACTIVE = 1;
    public static final int STATE_ACTIVE = 2;
    public int getState() { return 0; }
    public void setState(int s) { }
    public void setLabel(CharSequence l) { }
    public void setIcon(android.graphics.drawable.Icon i) { }
    public void updateTile() { }
}
