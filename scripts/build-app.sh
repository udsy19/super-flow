#!/bin/bash
# Builds build/Super Flow.app (release by default; `--debug` for a fast debug build; UNIVERSAL=1 for Apple silicon +
# Intel) and signs it with the project-local identity from scripts/signing-setup.sh (falls back to ad-hoc).
# DISTRIBUTION=appstore builds the Mac App Store edition instead (docs/app-store/README.md): compiled with -DAPP_STORE,
# bundle id $STORE_BUNDLE_ID, sandboxed entitlements, assembled at build/appstore/Super Flow.app and signed ad-hoc for
# local sandbox testing; scripts/package-appstore.sh re-signs it for the Store and wraps it in a .pkg.
# The whisper.cpp and llama.cpp frameworks (SwiftPM binary targets) are embedded in Contents/Frameworks, the
# executable gets the matching rpath, and every nested piece is signed before the bundle that seals it. The cue
# sounds and the bundled Silero VAD go into Contents/Resources. The script ends with static launch checks (nothing is
# launched and no window opens): entitlements, rpaths, every @rpath dependency present, resources in place.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
CONFIG=release; [ "${1:-}" = "--debug" ] && CONFIG=debug
DISTRIBUTION="${DISTRIBUTION:-direct}"
# The Store edition's bundle id: the one place it is defined (change it here before registering in App Store Connect).
STORE_BUNDLE_ID="com.udsy.superflow.appstore"
case "$DISTRIBUTION" in
  direct) SWIFT_FLAGS=(); OUT="$ROOT/build"; ENT="$ROOT/Resources/SuperFlow.entitlements" ;;
  appstore) SWIFT_FLAGS=(-Xswiftc -DAPP_STORE); OUT="$ROOT/build/appstore"; ENT="$ROOT/Resources/SuperFlow-AppStore.entitlements"
    # PROBE=1: a test-bed build with the headless sandbox probe (-DSANDBOX_PROBE), kept apart from the release bundle.
    if [ "${PROBE:-0}" = 1 ]; then SWIFT_FLAGS+=(-Xswiftc -DSANDBOX_PROBE); OUT="$ROOT/build/appstore-probe"; fi ;;
  *) echo "DISTRIBUTION must be direct or appstore (got $DISTRIBUTION)" >&2; exit 1 ;;
esac
# bash 3.2 + set -u: an empty array expands only through this guard.
FLAGS=(${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"})
PRODUCTS=(SuperFlow)
if [ "${UNIVERSAL:-0}" = 1 ]; then
  # Build each architecture separately (the CLT toolchain has no multi-arch build) and merge with lipo.
  for arch in arm64 x86_64; do
    for product in "${PRODUCTS[@]}"; do swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"} --product "$product" --triple "$arch-apple-macosx14.0"; done
  done
  ARM="$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)"
  INTEL="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx14.0 --show-bin-path)"
  BIN="$ROOT/build/universal"; mkdir -p "$BIN"; RES_BIN="$ARM"
  for product in "${PRODUCTS[@]}"; do lipo -create -output "$BIN/$product" "$ARM/$product" "$INTEL/$product"; done
else
  for product in "${PRODUCTS[@]}"; do swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"} --product "$product"; done
  BIN="$(swift build -c "$CONFIG" --show-bin-path)"; RES_BIN="$BIN"
fi

APP="$OUT/Super Flow.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
for product in "${PRODUCTS[@]}"; do cp "$BIN/$product" "$APP/Contents/MacOS/$product"; done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ "$DISTRIBUTION" = appstore ]; then
  # Own bundle id (both editions can be installed side by side), and no Apple Events: the Store edition sends none.
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $STORE_BUNDLE_ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :NSAppleEventsUsageDescription" "$APP/Contents/Info.plist"
  # Accessibility is asked for only to post ⌘V (and Return/Tab after it); nothing of other apps is read.
  /usr/libexec/PlistBuddy -c "Set :NSAccessibilityUsageDescription Super Flow uses Accessibility only to paste your dictated text into the app you are typing in, by sending the paste shortcut (⌘V) when you finish speaking, and to copy text you have selected (⌘C) when you ask it to rewrite that text. It never reads the content of other apps." "$APP/Contents/Info.plist"
fi
# Cue sounds (scripts/make-sounds.swift) and the bundled models (the Silero VAD, so VAD never downloads).
cp -R "$ROOT/Resources/Sounds" "$APP/Contents/Resources/Sounds"
cp -R "$ROOT/Resources/Models" "$APP/Contents/Resources/Models"
# Licence texts models ask to ship with the app (the NVIDIA Open Model License for Nemotron).
cp -R "$ROOT/Resources/Licenses" "$APP/Contents/Resources/Licenses"
# SwiftPM resource bundles of modules that declare resources (FluidAudio's, loaded through Bundle.module's
# Bundle.main.resourceURL lookup).
find "$RES_BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

# Native engines: the macOS slice of each xcframework SwiftPM downloaded (universal dynamic frameworks).
FRAMEWORKS=()
for name in whisper llama; do
  SLICE="$(find "$ROOT/.build/artifacts" -type d -path "*/$name.xcframework/macos-*" -name "$name.framework" | head -1)"
  [ -n "$SLICE" ] || { echo "Missing $name.framework in .build/artifacts; run swift build first" >&2; exit 1; }
  # cp -R keeps the Versions/Current symlink layout; dSYMs stay out of the bundle.
  cp -R "$SLICE" "$APP/Contents/Frameworks/$name.framework"
  FRAMEWORKS+=("$APP/Contents/Frameworks/$name.framework")
done
# The frameworks' install names are @rpath/<name>.framework/Versions/Current/<name>; SwiftPM linked the executable
# against the artifact folder, so replace that rpath with the bundle's.
for product in "${PRODUCTS[@]}"; do
  EXE="$APP/Contents/MacOS/$product"
  while IFS= read -r rpath; do
    [ -n "$rpath" ] && install_name_tool -delete_rpath "$rpath" "$EXE" 2>/dev/null || true
  done < <(otool -l "$EXE" | awk '/LC_RPATH/ {getline; getline; print $2}' | grep -F ".build/" || true)
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
done

ICONSET="$ROOT/build/AppIcon.iconset"
if [ ! -f "$ROOT/build/AppIcon.icns" ]; then
  swift "$ROOT/scripts/make-icon.swift" "$ICONSET" && iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

KC="$ROOT/.signing/super-flow.keychain-db"
if [ "$DISTRIBUTION" = appstore ]; then
  # App Store uploads are rejected when any bundled file carries com.apple.quarantine (downloaded xcframeworks can).
  chmod -R u+w "$APP"; xattr -cr "$APP"
  # Ad-hoc, inside-out, sandbox entitlements on the app only (frameworks carry none). The sandbox is enforced for
  # ad-hoc code, so this copy is the local test bed; package-appstore.sh re-signs with the Store identities.
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s - "$fw"; done
  codesign -f -s - --entitlements "$ENT" "$APP"
elif [ -f "$KC" ]; then
  security unlock-keychain -p superflow "$KC"
  ORIG=()
  while IFS= read -r line; do line="${line#"${line%%[![:space:]]*}"}"; line="${line//\"/}"; [ -n "$line" ] && ORIG+=("$line"); done < <(security list-keychains -d user)
  restore() { security list-keychains -d user -s "${ORIG[@]}"; }
  trap restore EXIT
  security list-keychains -d user -s "${ORIG[@]}" "$KC"
  # Nested code first (the frameworks), then the bundle that seals it; resource bundles are data the seal covers.
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s "Super Flow Local Signing" --keychain "$KC" -o runtime "$fw"; done
  codesign -f -s "Super Flow Local Signing" --keychain "$KC" -o runtime --entitlements "$ENT" "$APP"
  restore; trap - EXIT
else
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s - "$fw"; done
  codesign -f -s - --entitlements "$ENT" "$APP"
fi
codesign --verify --deep --strict "$APP"

# ---- Static launch checks. The app is never launched here (no GUI on a build machine); instead everything that would
# make it abort at launch is checked on disk.
fail() { echo "error: $*" >&2; exit 1; }
EXE="$APP/Contents/MacOS/SuperFlow"
SIGNED_ENT="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
if [ "$DISTRIBUTION" = appstore ]; then
  # Store: sandboxed, and none of the exceptions App Review rejects (docs/app-store/entitlements.md).
  for ent in com.apple.security.app-sandbox com.apple.security.device.audio-input com.apple.security.network.client; do
    grep -q "$ent" <<< "$SIGNED_ENT" || fail "entitlement $ent missing"
  done
  for ent in disable-library-validation allow-unsigned-executable-memory automation.apple-events temporary-exception get-task-allow; do
    if grep -q "$ent" <<< "$SIGNED_ENT"; then fail "the Store edition must not carry $ent"; fi
  done
  [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$STORE_BUNDLE_ID" ] || fail "bundle id is not $STORE_BUNDLE_ID"
  if strings -a "$EXE" | grep -q 'api.github.com/repos/.*/releases'; then fail "the Store edition still contains the GitHub updater"; fi
  # No Accessibility inspection of other apps in the Store binary (docs/app-store/privacy-and-permissions.md).
  if nm -u "$EXE" | grep -q '_AXUIElement'; then fail "the Store edition still links AXUIElement APIs: $(nm -u "$EXE" | grep _AXUIElement | tr '\n' ' ')"; fi
  if [ "${PROBE:-0}" != 1 ] && nm "$EXE" | grep -q 'SandboxProbe'; then fail "the release Store binary contains the sandbox probe"; fi
else
  # Embedded frameworks are signed without an Apple Team ID, so the hardened runtime refuses to load them unless library
  # validation is off. Without this the app aborts at launch; fail the build instead.
  if [ ${#FRAMEWORKS[@]} -gt 0 ] && ! grep -q disable-library-validation <<< "$SIGNED_ENT"; then
    fail "$APP embeds frameworks but lacks com.apple.security.cs.disable-library-validation"
  fi
  for ent in com.apple.security.device.audio-input com.apple.security.automation.apple-events; do
    grep -q "$ent" <<< "$SIGNED_ENT" || fail "entitlement $ent missing"
  done
fi
# rpaths: the bundle's Frameworks folder, and nothing pointing back into the build tree.
RPATHS="$(otool -l "$EXE" | awk '/LC_RPATH/ {getline; getline; print $2}')"
grep -qx '@executable_path/../Frameworks' <<< "$RPATHS" || fail "executable lacks the @executable_path/../Frameworks rpath"
if grep -q '\.build/' <<< "$RPATHS"; then fail "executable still has a build-tree rpath: $RPATHS"; fi
# Every @rpath dependency of the executable and of each framework must resolve inside Contents/Frameworks.
BINARIES=("$EXE")
for fw in "${FRAMEWORKS[@]}"; do name="$(basename "$fw" .framework)"; BINARIES+=("$fw/Versions/Current/$name"); done
for bin in "${BINARIES[@]}"; do
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    rel="${dep#@rpath/}"
    [ -e "$APP/Contents/Frameworks/$rel" ] || fail "$(basename "$bin") depends on $dep, which is not in Contents/Frameworks"
  done < <(otool -L "$bin" | awk 'NR > 1 && $1 ~ /^@rpath\// { print $1 }' | sort -u)
  otool -L "$bin" | awk 'NR > 1 { print $1 }' | grep -q '\.build/' && fail "$(basename "$bin") links into the build tree"
  if otool -L "$bin" | awk 'NR > 1 { print $1 }' | grep -qE '^/(opt/homebrew|usr/local)/'; then fail "$(basename "$bin") links a Homebrew library"; fi
done
# Resources the app expects at runtime.
for res in Resources/AppIcon.icns Resources/Sounds/dictationStart.wav Resources/Sounds/notificationError.wav \
           Resources/Models/vad/ggml-silero-v6.2.0.bin Resources/FluidAudio_FluidAudio.bundle Resources/Licenses/NVIDIA-Open-Model-License.txt; do
  [ -e "$APP/Contents/$res" ] || fail "missing $res in the bundle"
done
# Info.plist: the executable name and every usage description the permissions need.
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")" = "SuperFlow" ] || fail "CFBundleExecutable is not SuperFlow"
KEYS=(NSMicrophoneUsageDescription NSAudioCaptureUsageDescription NSCalendarsFullAccessUsageDescription NSAccessibilityUsageDescription)
[ "$DISTRIBUTION" = direct ] && KEYS+=(NSAppleEventsUsageDescription)
for key in "${KEYS[@]}"; do
  /usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist" >/dev/null 2>&1 || fail "Info.plist lacks $key"
done
echo "Static launch checks passed: entitlements, rpaths, @rpath dependencies, resources, Info.plist"
echo "Built $APP"
