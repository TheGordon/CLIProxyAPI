#!/bin/bash
# Sync local auth files to Railway deployment

set -e

LOCAL_AUTH_DIR="${1:-$HOME/.cli-proxy-api}"
RAILWAY_MOUNT_PATH="${2:-/root/.cli-proxy-api}"

echo "Syncing $LOCAL_AUTH_DIR to Railway..."

# Step 1: Create remote directory
echo "[1/4] Creating remote directory..."
railway ssh -- mkdir -p "$RAILWAY_MOUNT_PATH"
echo "  ✓ Directory created"

# Step 2: Clean any existing files
echo "[2/4] Cleaning existing files..."
railway ssh -- rm -rf "$RAILWAY_MOUNT_PATH"/*
echo "  ✓ Cleaned"

# Step 3: Upload files one by one
echo "[3/4] Uploading files..."
FILE_COUNT=0
for filepath in "$LOCAL_AUTH_DIR"/*; do
    file=$(basename "$filepath")
    if [ -f "$filepath" ]; then
        FILE_COUNT=$((FILE_COUNT + 1))
        echo "  Uploading: $file"

        # Encode file to base64
        B64_CONTENT=$(base64 -w0 "$filepath")
        echo "    Base64 size: ${#B64_CONTENT} bytes"

        # Write base64 to temp file on Railway (simple direct approach)
        echo "    Writing base64 to Railway..."
        railway ssh -- echo "$B64_CONTENT" \> /tmp/upload_${file}.b64

        # Verify base64 was written
        B64_SIZE=$(railway ssh -- wc -c /tmp/upload_${file}.b64 | awk '{print $1}')
        echo "    Remote base64 size: $B64_SIZE bytes"

        # Decode to final destination
        echo "    Decoding to final location..."
        railway ssh -- base64 -d /tmp/upload_${file}.b64 \> $RAILWAY_MOUNT_PATH/$file

        # Cleanup temp file
        railway ssh -- rm /tmp/upload_${file}.b64

        # Verify file size and checksum
        LOCAL_SIZE=$(wc -c < "$filepath")
        REMOTE_SIZE=$(railway ssh -- wc -c "$RAILWAY_MOUNT_PATH/$file" | awk '{print $1}')

        LOCAL_MD5=$(md5sum "$filepath" | awk '{print $1}')
        REMOTE_MD5=$(railway ssh -- md5sum "$RAILWAY_MOUNT_PATH/$file" | awk '{print $1}')

        if [ "$LOCAL_SIZE" = "$REMOTE_SIZE" ] && [ "$LOCAL_MD5" = "$REMOTE_MD5" ]; then
            echo "    ✓ $file ($LOCAL_SIZE bytes, md5: $LOCAL_MD5)"
        else
            echo "    ✗ $file verification failed!"
            echo "       Size - Local: $LOCAL_SIZE, Remote: $REMOTE_SIZE"
            echo "       MD5  - Local: $LOCAL_MD5, Remote: $REMOTE_MD5"
            exit 1
        fi
    fi
done

echo "  Total files uploaded: $FILE_COUNT"

# Step 4: Final verification
echo "[4/4] Verifying..."
railway ssh -- ls -lah "$RAILWAY_MOUNT_PATH"

echo ""
echo "✓ Success! Files synced to Railway."
