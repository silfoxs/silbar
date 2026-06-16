#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SilBar"
BUNDLE_ID="com.openai.silbar"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ENV_FILE="$ROOT_DIR/build.env"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Sources/SilBar/Resources/AppIcon.icns"
INSTALLER_BACKGROUND_RENDERER="$ROOT_DIR/script/create_dmg_background.swift"
INSTALLER_LAYOUT_SCRIPT="$ROOT_DIR/script/configure_dmg.applescript"
INSTALLER_STAGING_DIR="$DIST_DIR/package"
INSTALLER_BACKGROUND_DIR=".background"
INSTALLER_BACKGROUND_IMAGE="installer-background.png"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|package]" >&2
}

load_build_env() {
  local app_version_was_set=0
  local app_build_number_was_set=0
  local app_version_override="${APP_VERSION-}"
  local app_build_number_override="${APP_BUILD_NUMBER-}"

  [[ ${APP_VERSION+x} ]] && app_version_was_set=1
  [[ ${APP_BUILD_NUMBER+x} ]] && app_build_number_was_set=1

  if [[ -f "$BUILD_ENV_FILE" ]]; then
    set -a
    source "$BUILD_ENV_FILE"
    set +a
  fi

  if [[ "$app_version_was_set" -eq 1 ]]; then
    APP_VERSION="$app_version_override"
  fi
  if [[ "$app_build_number_was_set" -eq 1 ]]; then
    APP_BUILD_NUMBER="$app_build_number_override"
  fi
}

default_app_version() {
  local version
  if version="$(git -C "$ROOT_DIR" describe --tags --match 'Silbar-v[0-9]*' --match 'SilBar-v[0-9]*' --abbrev=0 2>/dev/null)"; then
    version="${version#Silbar-v}"
    echo "${version#SilBar-v}"
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

create_installer_background() {
  /usr/bin/swift -module-cache-path "${TMPDIR:-/tmp}/silbar-swift-module-cache" "$INSTALLER_BACKGROUND_RENDERER" "$1"
}

configure_installer_dmg() {
  local mount_dir="$1"
  /usr/bin/osascript "$INSTALLER_LAYOUT_SCRIPT" "$mount_dir" "$APP_NAME.app" "$mount_dir/$INSTALLER_BACKGROUND_DIR/$INSTALLER_BACKGROUND_IMAGE"
}

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|package)
    ;;
  *)
    usage
    exit 2
    ;;
esac

load_build_env

APP_VERSION="${APP_VERSION:-$(default_app_version)}"
if [[ -z "$APP_VERSION" ]]; then
  echo "错误: 未设置 APP_VERSION。请在 build.env 中设置 APP_VERSION 或创建 Silbar-v* 格式的 tag。" >&2
  exit 1
fi
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

if [[ ${#BUILD_FLAGS[@]} -gt 0 ]]; then
  swift build "${BUILD_FLAGS[@]}"
  BUILD_BINARY="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/$APP_NAME"
else
  swift build
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
fi

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
  INSTALLER_TEMP_PATH="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-$PACKAGE_ARCH-rw.dmg"
  INSTALLER_BACKGROUND_PATH="$INSTALLER_STAGING_DIR/$INSTALLER_BACKGROUND_DIR/$INSTALLER_BACKGROUND_IMAGE"
  INSTALLER_MOUNT_DIR=""
  INSTALLER_VOLUME_DIR=""

  cleanup_installer_mount() {
    if [[ -n "$INSTALLER_VOLUME_DIR" && -d "$INSTALLER_VOLUME_DIR" ]]; then
      /usr/bin/hdiutil detach "$INSTALLER_VOLUME_DIR" >/dev/null 2>&1 || true
      INSTALLER_VOLUME_DIR=""
    fi
    if [[ -d "/Volumes/$APP_NAME" ]]; then
      /usr/bin/hdiutil detach "/Volumes/$APP_NAME" >/dev/null 2>&1 || true
    fi
    if [[ -n "$INSTALLER_MOUNT_DIR" ]]; then
      rmdir "$INSTALLER_MOUNT_DIR" >/dev/null 2>&1 || true
      INSTALLER_MOUNT_DIR=""
    fi
  }

  trap cleanup_installer_mount EXIT

  rm -f "$INSTALLER_PATH" "$INSTALLER_TEMP_PATH"
  rm -rf "$INSTALLER_STAGING_DIR"
  mkdir -p "$INSTALLER_STAGING_DIR/$INSTALLER_BACKGROUND_DIR"
  cp -R "$APP_BUNDLE" "$INSTALLER_STAGING_DIR/"
  ln -s /Applications "$INSTALLER_STAGING_DIR/Applications"
  create_installer_background "$INSTALLER_BACKGROUND_PATH"
  /usr/bin/SetFile -a V "$INSTALLER_STAGING_DIR/$INSTALLER_BACKGROUND_DIR" >/dev/null 2>&1 || true

  hdiutil create -volname "$APP_NAME" -srcfolder "$INSTALLER_STAGING_DIR" -ov -format UDRW "$INSTALLER_TEMP_PATH" >/dev/null

  INSTALLER_MOUNT_DIR="$(mktemp -d "$DIST_DIR/dmg-mount.XXXXXX")"
  ATTACH_OUTPUT="$(hdiutil attach "$INSTALLER_TEMP_PATH" -nobrowse -readwrite -mountpoint "$INSTALLER_MOUNT_DIR")"
  if [[ -d "$INSTALLER_MOUNT_DIR/$APP_NAME.app" ]]; then
    INSTALLER_VOLUME_DIR="$INSTALLER_MOUNT_DIR"
  else
    INSTALLER_VOLUME_DIR="$(printf "%s\n" "$ATTACH_OUTPUT" | awk 'NF && $NF ~ /^\// { print $NF; exit }')"
  fi
  if [[ -z "$INSTALLER_VOLUME_DIR" || ! -d "$INSTALLER_VOLUME_DIR/$APP_NAME.app" ]]; then
    echo "failed to mount installer disk image" >&2
    exit 1
  fi

  /usr/bin/SetFile -a V "$INSTALLER_VOLUME_DIR/$INSTALLER_BACKGROUND_DIR" >/dev/null 2>&1 || true
  configure_installer_dmg "$INSTALLER_VOLUME_DIR"
  rm -rf "$INSTALLER_VOLUME_DIR/.fseventsd" "$INSTALLER_VOLUME_DIR/.Trashes"
  sync
  cleanup_installer_mount

  hdiutil convert "$INSTALLER_TEMP_PATH" -format UDZO -imagekey zlib-level=9 -o "$INSTALLER_PATH" >/dev/null
  rm -f "$INSTALLER_TEMP_PATH"
  trap - EXIT

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
