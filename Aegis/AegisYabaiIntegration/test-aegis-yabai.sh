#!/bin/bash

# Test script to verify Aegis-Yabai FIFO pipe integration

echo "Testing Aegis-Yabai FIFO Pipe Integration"
echo "=========================================="
echo ""

CONFIG_DIR="$HOME/.config/aegis"
PIPE_PATH="$CONFIG_DIR/yabai.pipe"
NOTIFY_SCRIPT="$CONFIG_DIR/aegis-yabai-notify"

# Test 1: Check if yabai is running
echo "1. Checking yabai..."
if pgrep -x "yabai" > /dev/null; then
    echo "   yabai is running"
else
    echo "   yabai is NOT running"
    echo "      Start it with: brew services start yabai"
    exit 1
fi

# Test 2: Check if config directory exists
echo ""
echo "2. Checking config directory..."
if [ -d "$CONFIG_DIR" ]; then
    echo "   Config directory exists: $CONFIG_DIR"
else
    echo "   Config directory not found: $CONFIG_DIR"
    echo "      Run setup-aegis-yabai.sh first"
    exit 1
fi

# Test 3: Check if notify script exists
echo ""
echo "3. Checking notification script..."
if [ -f "$NOTIFY_SCRIPT" ]; then
    echo "   Script exists: $NOTIFY_SCRIPT"
    if [ -x "$NOTIFY_SCRIPT" ]; then
        echo "   Script is executable"
    else
        echo "   Script is NOT executable"
        echo "      Fix with: chmod +x $NOTIFY_SCRIPT"
    fi
else
    echo "   Script not found: $NOTIFY_SCRIPT"
    echo "      Run setup-aegis-yabai.sh first"
    exit 1
fi

# Test 4: Check if FIFO pipe exists
echo ""
echo "4. Checking FIFO pipe..."
if [ -p "$PIPE_PATH" ]; then
    echo "   FIFO pipe exists: $PIPE_PATH"
else
    echo "   FIFO pipe not found (Aegis creates this when it starts)"
    echo "      Make sure Aegis is running"
fi

# Test 5: Check registered signals
echo ""
echo "5. Checking yabai signals..."
SIGNALS=$(yabai -m signal --list | grep -c "aegis_")
if [ "$SIGNALS" -gt 0 ]; then
    echo "   Found $SIGNALS Aegis signals registered"
    echo ""
    echo "   Registered signals:"
    yabai -m signal --list | grep aegis_ | while read -r line; do
        echo "      - $line"
    done
else
    echo "   No Aegis signals found"
    echo "      Run setup-aegis-yabai.sh to register signals"
    exit 1
fi

# Test 6: Test notification script (only if pipe exists)
echo ""
echo "6. Testing notification script..."
if [ -p "$PIPE_PATH" ]; then
    echo "   Sending test event to pipe..."
    YABAI_EVENT_TYPE="test_event" "$NOTIFY_SCRIPT"
    echo "   Test event sent (check Aegis logs for reception)"
else
    echo "   Skipping - FIFO pipe not available (start Aegis first)"
fi

# Test 7: Interactive test
echo ""
echo "7. Interactive test"
if [ -p "$PIPE_PATH" ]; then
    echo "   Monitoring FIFO pipe for events..."
    echo "   Switch to a different space or window now!"
    echo "   (Press Ctrl+C to stop)"
    echo ""

    # Read from pipe in a loop
    while true; do
        if read -r event < "$PIPE_PATH" 2>/dev/null; then
            echo "   Event received: $event"
        fi
    done
else
    echo "   Cannot run interactive test - FIFO pipe not available"
    echo "   Start Aegis first, then run this test again"
fi
