#!/bin/bash

set -e

WORKDIR="$HOME/PIF"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Using working directory: $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

wget -q -O versions.html "https://developer.android.com/about/versions"

echo "Finding latest Android version URL..."
LATEST_URL=$(grep -o 'https://developer.android.com/about/versions/[0-9][^"]*' versions.html | sort -ru | head -n1)
echo "Latest URL: $LATEST_URL"

wget -q -O latest.html "$LATEST_URL"

if grep -qE 'Developer Preview|tooltip>.*preview program' latest.html; then
  echo "Latest version is a developer preview. Falling back to previous version..."
  SECOND_LATEST_URL=$(grep -o 'https://developer.android.com/about/versions/[0-9][^"]*' versions.html | sort -ru | head -n2 | tail -n1)
  echo "Using: $SECOND_LATEST_URL"
  wget -q -O beta.html "$SECOND_LATEST_URL"
else
  echo "Latest version is stable. Proceeding..."
  cp latest.html beta.html
fi

echo "Extracting OTA page URL..."
OTA_PATH=$(grep -o 'href="[^"]*download-ota[^"]*"' beta.html | cut -d\" -f2 | head -n1)
OTA_PAGE="https://developer.android.com${OTA_PATH}"
echo "OTA page: $OTA_PAGE"

wget -q -O ota.html "$OTA_PAGE"

echo "Extracting device info and OTA link..."
MODEL=$(grep -A1 'tr id=' ota.html | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;' | head -n1)
OTA_LINK=$(grep -o -E 'href="([^"]+\.zip)"' ota.html | sed 's/href="//;s/"//g' | grep '_beta' | head -n1)

if [ -z "$OTA_LINK" ]; then
  echo "Failed to extract OTA link."
  exit 1
fi

if [[ "$OTA_LINK" != http* ]]; then
  OTA_LINK="https://developer.android.com${OTA_LINK}"
fi

echo "Found OTA link: $OTA_LINK"

OTA_ID=$(echo "$OTA_LINK" | sed -E 's/.*-([^-]+)-[^/]*\.zip/\1/i')
echo "Extracted OTA identifier: $OTA_ID"

if [ -f "$SCRIPT_DIR/pif.json" ]; then
  EXISTING_FP=$(jq -r .FINGERPRINT "$SCRIPT_DIR/pif.json" 2>/dev/null || echo "")
  if echo "$EXISTING_FP" | grep -iq "$OTA_ID"; then
    echo "PIF is already up to date. Skipping update."
    exit 0
  fi
fi

echo "Downloading OTA metadata..."
wget --show-progress -O metadata.txt "$OTA_LINK"

echo "Extracting fingerprint and security patch..."
FINGERPRINT=$(grep -am1 'post-build=' metadata.txt | cut -d= -f2)
SECURITY_PATCH=$(grep -am1 'security-patch-level=' metadata.txt | cut -d= -f2)

if [ -z "$FINGERPRINT" ] || [ -z "$SECURITY_PATCH" ]; then
  echo "Failed to extract necessary metadata. Exiting."
  exit 1
fi

FILENAME=$(basename "$OTA_LINK")
PRODUCT=$(echo "$FILENAME" | cut -d- -f1)
DEVICE=${PRODUCT%_beta}
RELEASE=$(echo "$FINGERPRINT"   | cut -d'/' -f3 | cut -d':' -f2)
ID=$(echo "$FINGERPRINT" | cut -d'/' -f4 | cut -d':' -f2)
INCREMENTAL=$(echo "$FINGERPRINT"   | cut -d'/' -f5 | cut -d':' -f1)
echo "Parsed PRODUCT=$PRODUCT, DEVICE=$DEVICE"

echo "Writing output to pif.json..."
cat <<EOF > "$SCRIPT_DIR/pif.json"
{
  "MANUFACTURER": "Google",
  "MODEL": "$MODEL",
  "FINGERPRINT": "$FINGERPRINT",
  "BRAND": "google",
  "PRODUCT": "$PRODUCT",
  "DEVICE": "$DEVICE",
  "VERSION.RELEASE": "16",
  "ID": "$ID",
  "VERSION.INCREMENTAL": "$INCREMENTAL",
  "TYPE": "user",
  "TAGS": "release-keys",
  "VERSION.SECURITY_PATCH": "$SECURITY_PATCH",
  "VERSION.DEVICE_INITIAL_SDK_INT": "32"
}
EOF

echo "Cleaning up temporary files..."
rm -f versions.html latest.html beta.html ota.html metadata.txt

echo "Done. Output written to: $SCRIPT_DIR/pif.json"
cat "$SCRIPT_DIR/pif.json"

