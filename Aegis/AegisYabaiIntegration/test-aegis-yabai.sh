#!/bin/bash

# Test script to verify Aegis-Yabai integration

echo "🧪 Testing Aegis-Yabai Integration"
echo "=================================="
echo ""

EVENT_FILE="/tmp/aegis_yabai_event"
NOTIFY_SCRIPT="/usr/local/bin/aegis-yabai-notify"

# Test 1: Check if yabai is running
echo "1️⃣  Checking yabai..."
if pgrep -x "yabai" > /dev/null; then
    echo "   ✅ yabai is running"
else
    echo "   ❌ yabai is NOT running"
    echo "      Start it with: brew services start yabai"
    exit 1
fi

# Test 2: Check if notify script exists
echo ""
echo "2️⃣  Checking notification script..."
if [ -f "$NOTIFY_SCRIPT" ]; then
    echo "   ✅ Script exists: $NOTIFY_SCRIPT"
    if [ -x "$NOTIFY_SCRIPT" ]; then
        echo "   ✅ Script is executable"
    else
        echo "   ❌ Script is NOT executable"
        echo "      Fix with: sudo chmod +x $NOTIFY_SCRIPT"
    fi
else
    echo "   ❌ Script not found: $NOTIFY_SCRIPT"
    echo "      Run setup-aegis-yabai.sh first"
    exit 1
fi

# Test 3: Check if event file exists
echo ""
echo "3️⃣  Checking event file..."
if [ -f "$EVENT_FILE" ]; then
    echo "   ✅ Event file exists: $EVENT_FILE"
else
    echo "   ⚠️  Event file doesn't exist (will be created automatically)"
    touch "$EVENT_FILE"
    echo "   ✅ Created event file"
fi

# Test 4: Test the notification script
echo ""
echo "4️⃣  Testing notification script..."
BEFORE=$(stat -f "%m" "$EVENT_FILE" 2>/dev/null || echo "0")
"$NOTIFY_SCRIPT"
sleep 0.1
AFTER=$(stat -f "%m" "$EVENT_FILE" 2>/dev/null || echo "0")

if [ "$AFTER" -gt "$BEFORE" ]; then
    echo "   ✅ Notification script works!"
else
    echo "   ❌ Notification script failed to update event file"
    exit 1
fi

# Test 5: Check registered signals
echo ""
echo "5️⃣  Checking yabai signals..."
SIGNALS=$(yabai -m signal --list | grep -c "aegis_")
if [ "$SIGNALS" -gt 0 ]; then
    echo "   ✅ Found $SIGNALS Aegis signals registered"
    echo ""
    echo "   Registered signals:"
    yabai -m signal --list | grep aegis_ | while read -r line; do
        echo "      • $line"
    done
else
    echo "   ❌ No Aegis signals found"
    echo "      Run setup-aegis-yabai.sh to register signals"
    exit 1
fi

# Test 6: Interactive test
echo ""
echo "6️⃣  Interactive test"
echo "   Monitoring $EVENT_FILE for changes..."
echo "   👉 Switch to a different space or window now!"
echo "   (Press Ctrl+C to stop)"
echo ""

LAST_MOD=$(stat -f "%m" "$EVENT_FILE" 2>/dev/null || echo "0")
COUNT=0

while true; do
    sleep 0.5
    CURRENT_MOD=$(stat -f "%m" "$EVENT_FILE" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MOD" -gt "$LAST_MOD" ]; then
        COUNT=$((COUNT + 1))
        echo "   ✅ Event detected! (#$COUNT) - Yabai is notifying Aegis correctly!"
        LAST_MOD=$CURRENT_MOD
    fi
done
