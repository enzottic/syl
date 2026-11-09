#!/bin/bash
# Captures the unfolded iPhone Duo's Stats screen for the App Store stats page.
# The Duo simulator can only be unfolded by hand (in Device Hub), and running UI tests folds it,
# so this launches the Debug app straight onto a tab with its -screenshot-tab flag instead.
# Usage: capture_duo_open.sh <output dir> [derived data path]
set -euo pipefail

OUTPUT_DIR="$1"
DERIVED_DATA="${2:-$(mktemp -d)}"
DEVICE_NAME="iPhone Duo"
BUNDLE_ID="me.enzottic.FinanceTracker-debug"
INNER_DISPLAY="3"
OUTPUT="$OUTPUT_DIR/$DEVICE_NAME-03-Stats-Open.png"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE_ID=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
devices = [d for runtime in json.load(sys.stdin)["devices"].values() for d in runtime if d["name"] == name]
print(devices[0]["udid"] if devices else "")
' "$DEVICE_NAME")
if [ -z "$DEVICE_ID" ]; then
  echo "No simulator named '$DEVICE_NAME'" >&2
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b > /dev/null

# A folded Duo's inner screen is solid black, so a shrunken copy has no nonzero color bytes (alpha is skipped).
probe=$(mktemp -d)
xcrun simctl io "$DEVICE_ID" screenshot --display="$INNER_DISPLAY" "$probe/inner.png" > /dev/null 2>&1
sips -z 4 4 -s format bmp "$probe/inner.png" --out "$probe/inner.bmp" > /dev/null
if ! tail -c 64 "$probe/inner.bmp" | od -An -v -tx1 | awk '{ for (i = 1; i <= NF; i++) if (i % 4 && $i != "00") found = 1 } END { exit !found }'; then
  echo "The iPhone Duo is folded. Unfold it in Device Hub, then run: fastlane capture_duo_open" >&2
  echo "Keeping any existing $(basename "$OUTPUT")." >&2
  exit 0
fi

xcodebuild build \
  -project "$PROJECT_DIR/FinanceTracker.xcodeproj" \
  -scheme "FinanceTracker-Screenshots" \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet

APP_PATH=$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" ! -name "*UITests*" | head -1)
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl status_bar "$DEVICE_ID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
# The first launch seeds data and may show What's New, so settle with a second launch.
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" -screenshot-tab stats > /dev/null
sleep 5
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" -screenshot-tab stats > /dev/null
sleep 5

mkdir -p "$OUTPUT_DIR"
xcrun simctl io "$DEVICE_ID" screenshot --display="$INNER_DISPLAY" "$OUTPUT" > /dev/null 2>&1
xcrun simctl status_bar "$DEVICE_ID" clear
echo "Captured $(basename "$OUTPUT")"
