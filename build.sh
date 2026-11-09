#!/bin/bash
# Builds and signs build/tvos-home.apk with plain SDK tools (no Gradle).
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${JAVA_HOME:-}" ] && [ -d "$HOME/.local/jdk-17.0.20.1+1/Contents/Home" ]; then
    JAVA_HOME="$HOME/.local/jdk-17.0.20.1+1/Contents/Home"
fi
if [ -n "${JAVA_HOME:-}" ]; then export JAVA_HOME; export PATH="$JAVA_HOME/bin:$PATH"; fi
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[ -d "$SDK" ] || SDK="$HOME/Android/Sdk"
BT="$SDK/build-tools/34.0.0"
JAR="$SDK/platforms/android-34/android.jar"
for f in "$BT/aapt2" "$BT/d8.bat" "$JAR"; do
    [ -e "$f" ] || { echo "Missing $f" >&2; exit 1; }
done

rm -rf build && mkdir -p build/gen build/classes build/dex

"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -o build/unsigned.apk -I "$JAR" --manifest AndroidManifest.xml \
    -A assets --java build/gen --min-sdk-version 24 --target-sdk-version 34 \
    --version-code "${VERSION_CODE:-15}" --version-name "${VERSION_NAME:-2.1.5}" build/res.zip

# FIX: Use a text file for Java sources to bypass Windows limits
find src build/gen -name '*.java' > build/java_sources.txt
javac -encoding UTF-8 --release 11 -classpath "$JAR" -d build/classes @build/java_sources.txt

# FIX: Bundle classes into a single jar file before passing to d8.bat
jar cf build/classes.jar -C build/classes .
"$BT/d8.bat" --release --min-api 24 --lib "$JAR" --output build/dex build/classes.jar
(cd build/dex && jar uf ../unsigned.apk classes.dex)

"$BT/zipalign" -f 4 build/unsigned.apk build/aligned.apk

if [ -n "${RELEASE_KEYSTORE:-}" ]; then
    "$BT/apksigner.bat" sign --ks "$RELEASE_KEYSTORE" --ks-pass env:RELEASE_KEYSTORE_PASS \
        --ks-key-alias "${RELEASE_KEY_ALIAS:-tvos-release}" --out build/tvos-home.apk build/aligned.apk
else
    KS=debug.keystore
    if [ ! -f "$KS" ]; then
        keytool -genkeypair -keystore "$KS" -storepass android -keypass android -alias debug \
            -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=tvOS Launcher debug" >/dev/null
    fi
    "$BT/apksigner.bat" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
        --out build/tvos-home.apk build/aligned.apk
    echo "Signed with the local debug key (development build)"
fi

echo "Built build/tvos-home.apk"
