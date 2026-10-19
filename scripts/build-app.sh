#!/bin/bash
# Builds build/Super Flow.app (release by default; `--debug` for a fast debug build; UNIVERSAL=1 for Apple silicon +
# Intel) and signs it with the project-local identity from scripts/signing-setup.sh (falls back to ad-hoc).
# The whisper.cpp and llama.cpp frameworks (SwiftPM binary targets) are embedded in Contents/Frameworks, the
# executable gets the matching rpath, and every nested piece is signed before the bundle that seals it. The cue
# sounds and the bundled Silero VAD go into Contents/Resources. The script ends with static launch checks (nothing is
# launched and no window opens): entitlements, rpaths, every @rpath dependency present, resources in place.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
CONFIG=release; [ "${1:-}" = "--debug" ] && CONFIG=debug
PRODUCTS=(SuperFlow)
if [ "${UNIVERSAL:-0}" = 1 ]; then
  # Build each architecture separately (the CLT toolchain has no multi-arch build) and merge with lipo.
  for arch in arm64 x86_64; do
    for product in "${PRODUCTS[@]}"; do swift build -c "$CONFIG" --product "$product" --triple "$arch-apple-macosx14.0"; done
  done
  ARM="$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)"
  INTEL="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx14.0 --show-bin-path)"
  BIN="$ROOT/build/universal"; mkdir -p "$BIN"; RES_BIN="$ARM"
  for product in "${PRODUCTS[@]}"; do lipo -create -output "$BIN/$product" "$ARM/$product" "$INTEL/$product"; done
else
  for product in "${PRODUCTS[@]}"; do swift build -c "$CONFIG" --product "$product"; done
  BIN="$(swift build -c "$CONFIG" --show-bin-path)"; RES_BIN="$BIN"
fi

APP="$ROOT/build/Super Flow.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
for product in "${PRODUCTS[@]}"; do cp "$BIN/$product" "$APP/Contents/MacOS/$product"; done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Cue sounds (scripts/make-sounds.swift) and the bundled models (the Silero VAD, so VAD never downloads).
cp -R "$ROOT/Resources/Sounds" "$APP/Contents/Resources/Sounds"
cp -R "$ROOT/Resources/Models" "$APP/Contents/Resources/Models"
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
ENT="$ROOT/Resources/SuperFlow.entitlements"
if [ -f "$KC" ]; then
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
# Embedded frameworks are signed without an Apple Team ID, so the hardened runtime refuses to load them unless library
# validation is off. Without this the app aborts at launch; fail the build instead.
if [ ${#FRAMEWORKS[@]} -gt 0 ] && ! codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q disable-library-validation; then
  fail "$APP embeds frameworks but lacks com.apple.security.cs.disable-library-validation"
fi
for ent in com.apple.security.device.audio-input com.apple.security.automation.apple-events; do
  codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "$ent" || fail "entitlement $ent missing"
done
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
done
# Resources the app expects at runtime.
for res in Resources/AppIcon.icns Resources/Sounds/dictationStart.wav Resources/Sounds/notificationError.wav \
           Resources/Models/vad/ggml-silero-v6.2.0.bin Resources/FluidAudio_FluidAudio.bundle; do
  [ -e "$APP/Contents/$res" ] || fail "missing $res in the bundle"
done
# Info.plist: the executable name and every usage description the permissions need.
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")" = "SuperFlow" ] || fail "CFBundleExecutable is not SuperFlow"
for key in NSMicrophoneUsageDescription NSAudioCaptureUsageDescription NSCalendarsFullAccessUsageDescription NSAppleEventsUsageDescription \
           NSAccessibilityUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist" >/dev/null 2>&1 || fail "Info.plist lacks $key"
done
echo "Static launch checks passed: entitlements, rpaths, @rpath dependencies, resources, Info.plist"
echo "Built $APP"
