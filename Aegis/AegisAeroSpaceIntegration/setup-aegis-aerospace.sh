#!/bin/bash

# Aegis - AeroSpace Integration Setup Script
# This script sets up the FIFO pipe notification system for Aegis + AeroSpace

set -e

echo "Setting up Aegis <-> AeroSpace FIFO pipe integration..."

# 1. Create config directory
CONFIG_DIR="$HOME/.config/aegis"
NOTIFY_SCRIPT="$CONFIG_DIR/aegis-aerospace-notify"

echo "Creating config directory at $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# 2. Create the notification script
echo "Creating notification script at $NOTIFY_SCRIPT"

cat > "$NOTIFY_SCRIPT" << 'EOF'
#!/bin/bash
# Aegis-AeroSpace FIFO Pipe Notification Script
# This script sends workspace change events to Aegis via a FIFO pipe

PIPE_PATH="$HOME/.config/aegis/aerospace.pipe"

# Check if pipe exists
if [ ! -p "$PIPE_PATH" ]; then
    exit 0
fi

# Send event to the pipe (non-blocking)
echo "workspace_changed" > "$PIPE_PATH" 2>/dev/null &
EOF

chmod +x "$NOTIFY_SCRIPT"
echo "Created notification script"

# 3. Check if aerospace is installed
if ! command -v aerospace &> /dev/null; then
    echo "Warning: aerospace CLI not found. Please install AeroSpace first."
    echo "  Install with: brew install --cask nikitabobko/tap/aerospace"
    exit 1
fi

echo "Found aerospace at $(which aerospace)"

# 4. Check AeroSpace config for exec-on-workspace-change
AEROSPACE_CONFIG="${AEROSPACE_CONFIG:-$HOME/.aerospace.toml}"
AEGIS_MARKER="# AEGIS_INTEGRATION"

SNIPPET="exec-on-workspace-change = ['/bin/bash', '-c', '$HOME/.config/aegis/aegis-aerospace-notify']"

if [ -f "$AEROSPACE_CONFIG" ]; then
    if grep -q "$AEGIS_MARKER" "$AEROSPACE_CONFIG"; then
        echo "Aegis integration already in AeroSpace config (will persist across restarts)"
    elif grep -q "exec-on-workspace-change" "$AEROSPACE_CONFIG"; then
        echo ""
        echo "WARNING: exec-on-workspace-change already exists in $AEROSPACE_CONFIG"
        echo "AeroSpace only supports one exec-on-workspace-change callback."
        echo ""
        echo "You can chain both commands by editing your config manually."
        echo "Replace your existing exec-on-workspace-change with something like:"
        echo ""
        echo "  exec-on-workspace-change = ['/bin/bash', '-c', 'your-existing-command; \$HOME/.config/aegis/aegis-aerospace-notify']"
        echo ""
    else
        echo ""
        echo "Found AeroSpace config at: $AEROSPACE_CONFIG"
        echo ""
        echo "Would you like to automatically add Aegis integration? [y/N]"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "" >> "$AEROSPACE_CONFIG"
            cat >> "$AEROSPACE_CONFIG" << TOML_EOF

$AEGIS_MARKER
$SNIPPET
TOML_EOF
            echo "Added exec-on-workspace-change to $AEROSPACE_CONFIG"
            echo ""
            echo "Reloading AeroSpace config..."
            aerospace reload-config 2>/dev/null || echo "  (reload failed — restart AeroSpace manually)"
        else
            echo ""
            echo "Skipped. To add manually, put this line in your $AEROSPACE_CONFIG:"
            echo ""
            echo "  $SNIPPET"
        fi
    fi
else
    echo ""
    echo "No AeroSpace config found at $AEROSPACE_CONFIG"
    echo ""
    echo "Would you like to create one with Aegis integration? [y/N]"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        cat > "$AEROSPACE_CONFIG" << TOML_EOF
# AeroSpace config
# See https://nikitabobko.github.io/AeroSpace/guide for full reference

# AEGIS_INTEGRATION
exec-on-workspace-change = ['/bin/bash', '-c', '\$HOME/.config/aegis/aegis-aerospace-notify']
TOML_EOF
        echo "Created $AEROSPACE_CONFIG with Aegis integration"
        echo ""
        echo "Reloading AeroSpace config..."
        aerospace reload-config 2>/dev/null || echo "  (reload failed — restart AeroSpace manually)"
    else
        echo ""
        echo "Skipped. To add manually, create $AEROSPACE_CONFIG with:"
        echo ""
        echo "  $SNIPPET"
        echo ""
        echo "To specify a custom config location, run:"
        echo "  AEROSPACE_CONFIG=/path/to/your/.aerospace.toml ./setup-aegis-aerospace.sh"
    fi
fi

# 5. Save snippet for reference
cat > "$CONFIG_DIR/aerospace-config-snippet.toml" << 'SNIPPET_EOF'
# Aegis Integration — add this to your .aerospace.toml
# Notifies Aegis instantly when you switch workspaces
exec-on-workspace-change = ['/bin/bash', '-c', '$HOME/.config/aegis/aegis-aerospace-notify']
SNIPPET_EOF

echo ""
echo "Setup complete!"
echo ""
echo "The FIFO pipe will be created automatically by Aegis when it starts."
echo "Config snippet saved to: $CONFIG_DIR/aerospace-config-snippet.toml"
echo ""
echo "To verify the setup is working:"
echo "  1. Run Aegis and check the logs for 'FIFO pipe monitoring active'"
echo "  2. Switch workspaces and watch for instant updates!"
