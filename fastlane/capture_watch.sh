#!/bin/bash
# Captures Apple Watch App Store screenshots from the Debug watch app's built-in preview fixture.
# snapshot can't drive watchOS, so this launches each page directly with the app's
# simulator-only -watch-preview / -watch-page flags and grabs the simulator screen.
# Usage: capture_watch.sh <output dir> [derived data path]
set -euo pipefail

OUTPUT_DIR="$1"
DERIVED_DATA="${2:-$(mktemp -d)}"
DEVICE_NAME="Apple Watch Ultra 4 (49mm)"
BUNDLE_ID="me.enzottic.FinanceTracker-debug.watchkitapp"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Page tags from SageDashboardView, paired with the output names that order them in App Store Connect.
PAGES=("overview:01-Overview" "Needs:02-Needs" "Wants:03-Wants" "Savings:04-Savings" "trends:05-Trends")

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

xcodebuild build \
  -project "$PROJECT_DIR/FinanceTracker.xcodeproj" \
  -scheme "FinanceTrackerWatch Watch App" \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet

APP_PATH=$(find "$DERIVED_DATA/Build/Products/Debug-watchsimulator" -maxdepth 1 -name "*.app" | head -1)

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b > /dev/null
xcrun simctl status_bar "$DEVICE_ID" override --time "9:41" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$DEVICE_NAME"-*.png
for page in "${PAGES[@]}"; do
  tag="${page%%:*}"
  name="${page#*:}"
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" -watch-preview -watch-page "$tag" > /dev/null
  # Let the page settle and its ring animations finish.
  sleep 4
  xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/$DEVICE_NAME-$name.png" > /dev/null 2>&1
  echo "Captured $name"
done

xcrun simctl status_bar "$DEVICE_ID" clear 2>/dev/null || true
