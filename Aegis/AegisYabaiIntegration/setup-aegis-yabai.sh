#!/bin/bash

# Aegis - Yabai Integration Setup Script
# This script sets up the FIFO pipe notification system for Aegis

set -e

echo "🚀 Setting up Aegis <-> Yabai FIFO pipe integration..."

# 1. Create config directory
CONFIG_DIR="$HOME/.config/aegis"
PIPE_PATH="$CONFIG_DIR/yabai.pipe"
NOTIFY_SCRIPT="$CONFIG_DIR/aegis-yabai-notify"

echo "📁 Creating config directory at $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
echo "✅ Config directory ready"

# 2. Create the notification script (no sudo required - user directory)
echo "📝 Creating notification script at $NOTIFY_SCRIPT"

cat > "$NOTIFY_SCRIPT" << 'EOF'
#!/bin/bash
# Aegis-Yabai FIFO Pipe Notification Script
# This script sends yabai event names to Aegis via a FIFO pipe

PIPE_PATH="$HOME/.config/aegis/yabai.pipe"

# Check if pipe exists
if [ ! -p "$PIPE_PATH" ]; then
    exit 0
fi

# Send event type to the pipe (non-blocking)
# The YABAI_* environment variables are set by yabai when calling this script
# We use timeout to prevent hanging if Aegis isn't reading
echo "$YABAI_EVENT_TYPE" 2>/dev/null | timeout 0.1s tee "$PIPE_PATH" > /dev/null 2>&1 &
EOF

# Make it executable (no sudo needed)
chmod +x "$NOTIFY_SCRIPT"
echo "✅ Created notification script"

# 3. Check if yabai is installed
if ! command -v yabai &> /dev/null; then
    echo "⚠️  Warning: yabai not found. Please install yabai first."
    echo "   Install with: brew install koekeishiya/formulae/yabai"
    exit 1
fi

echo "✅ Found yabai at $(which yabai)"

# 4. Remove any existing Aegis signals
echo "🧹 Cleaning up old signals..."
yabai -m signal --remove aegis_space_changed 2>/dev/null || true
yabai -m signal --remove aegis_space_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_focused 2>/dev/null || true
yabai -m signal --remove aegis_window_created 2>/dev/null || true
yabai -m signal --remove aegis_window_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_moved 2>/dev/null || true
yabai -m signal --remove aegis_application_front_switched 2>/dev/null || true

# 5. Register yabai signals with YABAI_EVENT_TYPE environment variable
echo "📡 Registering yabai signals..."

yabai -m signal --add event=space_changed action="YABAI_EVENT_TYPE=space_changed $NOTIFY_SCRIPT" label=aegis_space_changed
echo "  ✓ space_changed"

yabai -m signal --add event=space_destroyed action="YABAI_EVENT_TYPE=space_destroyed $NOTIFY_SCRIPT" label=aegis_space_destroyed
echo "  ✓ space_destroyed"

yabai -m signal --add event=window_focused action="YABAI_EVENT_TYPE=window_focused $NOTIFY_SCRIPT" label=aegis_window_focused
echo "  ✓ window_focused"

yabai -m signal --add event=window_created action="YABAI_EVENT_TYPE=window_created $NOTIFY_SCRIPT" label=aegis_window_created
echo "  ✓ window_created"

yabai -m signal --add event=window_destroyed action="YABAI_EVENT_TYPE=window_destroyed $NOTIFY_SCRIPT" label=aegis_window_destroyed
echo "  ✓ window_destroyed"

yabai -m signal --add event=window_moved action="YABAI_EVENT_TYPE=window_moved $NOTIFY_SCRIPT" label=aegis_window_moved
echo "  ✓ window_moved"

yabai -m signal --add event=application_front_switched action="YABAI_EVENT_TYPE=application_front_switched $NOTIFY_SCRIPT" label=aegis_application_front_switched
echo "  ✓ application_front_switched"

# 6. Verify signals are registered
echo ""
echo "📋 Registered signals:"
yabai -m signal --list | grep aegis

echo ""
echo "✅ Runtime setup complete!"
echo ""

# 7. Check if yabairc needs updating for persistence
# Default location, can be overridden with YABAIRC environment variable
YABAIRC="${YABAIRC:-$HOME/.config/yabai/yabairc}"
AEGIS_MARKER="# AEGIS_INTEGRATION_START"

if [ -f "$YABAIRC" ]; then
    if grep -q "$AEGIS_MARKER" "$YABAIRC"; then
        echo "✅ Aegis integration already in yabairc (will persist across restarts)"
    else
        echo ""
        echo "⚠️  IMPORTANT: Signals are registered but will be lost when yabai restarts."
        echo ""
        echo "Found yabai config at: $YABAIRC"
        echo ""
        echo "Would you like to automatically add Aegis integration to yabairc? [y/N]"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "" >> "$YABAIRC"
            cat >> "$YABAIRC" << 'YABAI_EOF'

# AEGIS_INTEGRATION_START
# Aegis window manager integration - DO NOT EDIT THIS SECTION
AEGIS_NOTIFY="$HOME/.config/aegis/aegis-yabai-notify"
yabai -m signal --remove aegis_space_changed 2>/dev/null || true
yabai -m signal --remove aegis_space_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_focused 2>/dev/null || true
yabai -m signal --remove aegis_window_created 2>/dev/null || true
yabai -m signal --remove aegis_window_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_moved 2>/dev/null || true
yabai -m signal --remove aegis_application_front_switched 2>/dev/null || true
yabai -m signal --add event=space_changed action="YABAI_EVENT_TYPE=space_changed $AEGIS_NOTIFY" label=aegis_space_changed
yabai -m signal --add event=space_destroyed action="YABAI_EVENT_TYPE=space_destroyed $AEGIS_NOTIFY" label=aegis_space_destroyed
yabai -m signal --add event=window_focused action="YABAI_EVENT_TYPE=window_focused $AEGIS_NOTIFY" label=aegis_window_focused
yabai -m signal --add event=window_created action="YABAI_EVENT_TYPE=window_created $AEGIS_NOTIFY" label=aegis_window_created
yabai -m signal --add event=window_destroyed action="YABAI_EVENT_TYPE=window_destroyed $AEGIS_NOTIFY" label=aegis_window_destroyed
yabai -m signal --add event=window_moved action="YABAI_EVENT_TYPE=window_moved $AEGIS_NOTIFY" label=aegis_window_moved
yabai -m signal --add event=application_front_switched action="YABAI_EVENT_TYPE=application_front_switched $AEGIS_NOTIFY" label=aegis_application_front_switched
# AEGIS_INTEGRATION_END
YABAI_EOF
            echo "✅ Added Aegis integration to $YABAIRC"
        else
            echo ""
            echo "Skipped. To add manually later, copy the snippet from:"
            echo "  ~/.config/aegis/yabairc-snippet.sh"

            # Save snippet for manual use
            cat > "$CONFIG_DIR/yabairc-snippet.sh" << 'SNIPPET_EOF'
# AEGIS_INTEGRATION_START
# Aegis window manager integration - add this to your yabairc
AEGIS_NOTIFY="$HOME/.config/aegis/aegis-yabai-notify"
yabai -m signal --remove aegis_space_changed 2>/dev/null || true
yabai -m signal --remove aegis_space_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_focused 2>/dev/null || true
yabai -m signal --remove aegis_window_created 2>/dev/null || true
yabai -m signal --remove aegis_window_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_moved 2>/dev/null || true
yabai -m signal --remove aegis_application_front_switched 2>/dev/null || true
yabai -m signal --add event=space_changed action="YABAI_EVENT_TYPE=space_changed $AEGIS_NOTIFY" label=aegis_space_changed
yabai -m signal --add event=space_destroyed action="YABAI_EVENT_TYPE=space_destroyed $AEGIS_NOTIFY" label=aegis_space_destroyed
yabai -m signal --add event=window_focused action="YABAI_EVENT_TYPE=window_focused $AEGIS_NOTIFY" label=aegis_window_focused
yabai -m signal --add event=window_created action="YABAI_EVENT_TYPE=window_created $AEGIS_NOTIFY" label=aegis_window_created
yabai -m signal --add event=window_destroyed action="YABAI_EVENT_TYPE=window_destroyed $AEGIS_NOTIFY" label=aegis_window_destroyed
yabai -m signal --add event=window_moved action="YABAI_EVENT_TYPE=window_moved $AEGIS_NOTIFY" label=aegis_window_moved
yabai -m signal --add event=application_front_switched action="YABAI_EVENT_TYPE=application_front_switched $AEGIS_NOTIFY" label=aegis_application_front_switched
# AEGIS_INTEGRATION_END
SNIPPET_EOF
            echo "  Snippet saved to: $CONFIG_DIR/yabairc-snippet.sh"
        fi
    fi
else
    echo "⚠️  No yabairc found at $YABAIRC"
    echo "   Signals will work now but won't persist across yabai restarts."
    echo ""
    echo "   To specify a custom location, run:"
    echo "   YABAIRC=/path/to/your/yabairc ./setup-aegis-yabai.sh"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "The FIFO pipe will be created automatically by Aegis when it starts."
echo ""
echo "To verify the setup is working:"
echo "  1. Run Aegis and check the logs for 'FIFO pipe monitoring active'"
echo "  2. Switch spaces/windows and watch for instant updates!"
