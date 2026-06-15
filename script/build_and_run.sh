#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SilBar"
BUNDLE_ID="com.openai.silbar"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Sources/SilBar/Resources/AppIcon.icns"
INSTALLER_STAGING_DIR="$DIST_DIR/package"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|package]" >&2
}

default_app_version() {
  local version
  if version="$(git -C "$ROOT_DIR" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null)"; then
    echo "${version#v}"
  else
    echo "0.1.0"
  fi
}

sanitize_filename_part() {
  printf "%s" "$1" | LC_CTYPE=C tr -c "A-Za-z0-9._-" "-" | sed -E "s/^-+//; s/-+$//"
}

detect_binary_arch() {
  local binary_info
  binary_info="$(file "$APP_BINARY")"

  if [[ "$binary_info" == *"universal binary"* ]] || [[ "$binary_info" == *"arm64"* && "$binary_info" == *"x86_64"* ]]; then
    echo "universal"
  elif [[ "$binary_info" == *"arm64"* ]]; then
    echo "arm64"
  elif [[ "$binary_info" == *"x86_64"* ]]; then
    echo "x86_64"
  else
    uname -m
  fi
}

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|package)
    ;;
  *)
    usage
    exit 2
    ;;
esac

APP_VERSION="${APP_VERSION:-$(default_app_version)}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"

if [[ "$MODE" != "package" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      break
    fi
    sleep 0.25
  done
fi

BUILD_FLAGS=()
if [[ "$MODE" == "package" ]]; then
  BUILD_FLAGS=(--configuration release)
fi

swift build "${BUILD_FLAGS[@]}"
BUILD_BINARY="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

if [[ "$MODE" == "package" ]]; then
  APP_ARCH="$(detect_binary_arch)"
  PACKAGE_VERSION="$(sanitize_filename_part "$APP_VERSION")"
  PACKAGE_ARCH="$(sanitize_filename_part "$APP_ARCH")"
  INSTALLER_PATH="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-$PACKAGE_ARCH.dmg"

  rm -f "$INSTALLER_PATH"
  rm -rf "$INSTALLER_STAGING_DIR"
  mkdir -p "$INSTALLER_STAGING_DIR"
  cp -R "$APP_BUNDLE" "$INSTALLER_STAGING_DIR/"
  hdiutil create -volname "$APP_NAME" -srcfolder "$INSTALLER_STAGING_DIR" -ov -format UDZO "$INSTALLER_PATH" >/dev/null
  echo "$INSTALLER_PATH"
  exit 0
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..10}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.5
    done
    exit 1
    ;;
  *)
    usage
    exit 2
    ;;
esac
