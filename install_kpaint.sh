#!/bin/bash

set -euo pipefail

DO_ICON="false"

if type rsvg-convert > /dev/null; then
	DO_ICON="true"
else
	if type brew > /dev/null; then
		if [ "$EUID" -eq 0 ]; then
			echo "Error: Start the script as a regular user, without sudo" >&2
			exit 1
		fi
		brew install librsvg
	else
		echo "Brew is missing, skipping icon fix"
	fi
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Rest of the script requires root privileges. Elevating..."
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
	chmod +x "$SCRIPT_PATH"
	exec sudo env "$SCRIPT_PATH" "$@"
fi

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

KDE_DIR="https://cdn.kde.org/ci-builds/graphics/kolourpaint/master/macos-arm64/"
SVG_URL="https://apps.kde.org/app-icons/org.kde.kolourpaint.svg"

echo "==> Finding latest DMG..."

DMG_URL=$(curl -fsSL "$KDE_DIR" \
    | grep -oE 'href="[^"]+\.dmg"' \
    | head -n1 \
    | sed 's/href="//;s/"//' )

if [[ -z "$DMG_URL" ]]; then
    echo "Failed to locate DMG file."
    exit 1
fi

if [[ "$DMG_URL" != http* ]]; then
    DMG_URL="${KDE_DIR}${DMG_URL}"
fi

DMG_FILE=$(basename "$DMG_URL")

echo "==> Downloading:"
echo "$DMG_URL"

curl -L -o "$DMG_FILE" "$DMG_URL"

echo "==> Mounting DMG..."

MOUNT_POINT=$(hdiutil attach "$DMG_FILE" -nobrowse | awk '/Volumes/ {print substr($0, index($0,$3))}' | tail -1)

echo "Mounted at:"
echo "$MOUNT_POINT"

APP_SRC=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)

if [[ ! -d "$APP_SRC" ]]; then
    echo "Could not locate .app in DMG."
    exit 1
fi

APP_DST="/Applications/$(basename "$APP_SRC")"

echo "==> Replacing existing app..."

sudo rm -rf "$APP_DST"
sudo cp -R "$APP_SRC" "$APP_DST"

echo "==> Unmounting DMG..."
hdiutil detach "$MOUNT_POINT"

if [[ "$DO_ICON" == "true" ]]; then
	echo "==> Downloading SVG icon..."
	curl -L -o kolourpaint.svg "$SVG_URL"


	ICONSET="$WORKDIR/icon.iconset"

	mkdir -p "$ICONSET"

	echo "==> Generating iconset..."
	echo "if rsvg-convert is missing install it through brew"
	echo "brew install librsvg"

	for SIZE in 16 32 64 128 256 512 1024
	do
		rsvg-convert \
		  -w "$SIZE" \
		  -h "$SIZE" \
		  kolourpaint.svg \
		  > "$ICONSET/icon_${SIZE}x${SIZE}.png"
	done

	cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
	cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
	cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
	cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
	cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"

	echo "==> Creating ICNS..."

	iconutil -c icns "$ICONSET"

	RESOURCE_ICON="$APP_DST/Contents/Resources/kolourpaint_SRCS.icns"

	sudo cp icon.icns "$RESOURCE_ICON"
fi

echo "==> Fixing permissions..."

sudo chown -R root:wheel "$APP_DST"
sudo chmod -R go+rX "$APP_DST"

echo "==> Removing quarantine attributes..."

sudo xattr -dr com.apple.quarantine "$APP_DST" || true

echo "==> Refreshing LaunchServices..."

touch "$APP_DST"

echo "==> Launching application..."

open "$APP_DST" || true
sleep 3

echo "==> Killing application..."

pkill -x "kolourpaint"
sleep 3

#Code above brut-forces enabling, opening and killing the app 
#so it is not needed for now but I left it in case new mac updates don't allow it anymore
#clear
#echo
#echo "If macOS blocks the app:"
#echo "Settings -> Privacy & Security -> click 'Open Anyway'"
#echo
#echo "==> Opening Security settings..."
#open "x-apple.systempreferences:com.apple.preference.security"
#echo 
#echo "=== WARNING! ==="
#echo "GUI fix can only be applied after app was started for the first time!"
#echo "If the app did not start, open it manually"
#echo "Once kolourpaint was started, you can close it rightaway."
#echo 
#read -n 1 -s -r -p "Press any key to continue after kolourpaint was oppened..."

PLIST="$APP_DST/Contents/Info.plist"

echo "==> Patching Info.plist..."

if ! /usr/libexec/PlistBuddy -c "Print :NSRequiresAquaSystemAppearance" "$PLIST" >/dev/null 2>&1; then
    sudo /usr/libexec/PlistBuddy \
        -c "Add :NSRequiresAquaSystemAppearance bool true" \
        "$PLIST"
fi

echo "==> Launching application..."
open "$APP_DST" || true
sleep 3

echo
echo "=== DONE! ===" 
read -n 1 -s -r -p "Press any key to end the script..."


