#!/usr/bin/env bash
# Construit l'APK « PerfDeck » sans Gradle ni Android Studio (même méthode que salonos-mobile) :
#   aapt (ressources) -> javac (Java 8) -> dx (dex) -> zipalign -> apksigner
# Outils (Ubuntu/Debian) : apt install aapt dalvik-exchange zipalign apksigner android-sdk-platform-23 openjdk-17-jdk-headless
#
# Clé de signature : android/keystore/perfdeck.jks (jamais dans le dépôt, à garder précieusement :
# les mises à jour de l'appli doivent être signées avec la même clé).
#   PERFDECK_KEYSTORE  chemin de la clé (défaut : android/keystore/perfdeck.jks)
#   PERFDECK_KEY_PASS  mot de passe (défaut : contenu de android/keystore/password.txt, créé avec la clé)
#   PERFDECK_VERSION   versionName à publier (ex. 1.0.3) ; versionCode = dernier nombre
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SDK_JAR="${ANDROID_JAR:-/usr/lib/android-sdk/platforms/android-23/android.jar}"
BUILD="$HERE/build"
OUT="$HERE/dist/PerfDeck.apk"
KEYSTORE="${PERFDECK_KEYSTORE:-$HERE/keystore/perfdeck.jks}"
PASSFILE="$(dirname "$KEYSTORE")/password.txt"

rm -rf "$BUILD"
mkdir -p "$BUILD/gen" "$BUILD/classes" "$HERE/dist"

# Version : PERFDECK_VERSION=1.0.7 -> versionName 1.0.7, versionCode 7
MANIFEST="$HERE/AndroidManifest.xml"
if [ -n "${PERFDECK_VERSION:-}" ]; then
  CODE="${PERFDECK_VERSION##*.}"
  sed -e "s/android:versionCode=\"[0-9]*\"/android:versionCode=\"$CODE\"/" \
      -e "s/android:versionName=\"[^\"]*\"/android:versionName=\"$PERFDECK_VERSION\"/" "$MANIFEST" > "$BUILD/AndroidManifest.xml"
  MANIFEST="$BUILD/AndroidManifest.xml"
fi

echo "1/5 Ressources"
aapt package -f -m \
  -M "$MANIFEST" \
  -S "$HERE/res" \
  -I "$SDK_JAR" \
  -J "$BUILD/gen" \
  -F "$BUILD/unsigned.apk"

echo "2/5 Compilation Java"
javac -source 8 -target 8 -encoding UTF-8 -nowarn -Xlint:-options \
  -bootclasspath "$SDK_JAR" -classpath "$SDK_JAR" \
  -d "$BUILD/classes" \
  $(find "$HERE/src" "$BUILD/gen" -name '*.java')

echo "3/5 Conversion Dalvik"
dalvik-exchange --dex --min-sdk-version=24 --output="$BUILD/classes.dex" "$BUILD/classes"
(cd "$BUILD" && aapt add -f unsigned.apk classes.dex > /dev/null)

echo "4/5 Alignement"
zipalign -f -p 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"

echo "5/5 Signature"
if [ ! -f "$KEYSTORE" ]; then
  # Clé créée une seule fois, avec un mot de passe aléatoire rangé à côté (dossier ignoré par git)
  mkdir -p "$(dirname "$KEYSTORE")"
  openssl rand -hex 16 > "$PASSFILE"
  KP="$(cat "$PASSFILE")"
  keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storetype PKCS12 -storepass "$KP" -keypass "$KP" \
    -alias perfdeck -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=PerfDeck, O=Lucas-tsl, C=FR" > /dev/null 2>&1
  echo "Nouvelle clé de signature : $KEYSTORE (garde-la avec $PASSFILE)"
fi
KEY_PASS="${PERFDECK_KEY_PASS:-$(cat "$PASSFILE" 2>/dev/null || true)}"
apksigner sign --ks "$KEYSTORE" --ks-pass "pass:$KEY_PASS" --key-pass "pass:$KEY_PASS" \
  --ks-key-alias perfdeck --min-sdk-version 24 --out "$OUT" "$BUILD/aligned.apk"
apksigner verify "$OUT"

# Copie servie par le PC au téléphone (http://PC:8765/PerfDeck.apk) et mise à jour par PerfUpdate
mkdir -p "$REPO/release" && cp "$OUT" "$REPO/release/PerfDeck.apk"
echo "APK prête : $OUT ($(du -h "$OUT" | cut -f1)), copiée dans release/PerfDeck.apk"
