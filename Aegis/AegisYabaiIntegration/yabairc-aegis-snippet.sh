#!/usr/bin/env sh

# ============================================
# Aegis Integration for .yabairc
# ============================================
# Add this section to your ~/.yabairc file to automatically
# set up Aegis integration when yabai starts
#
# OR run the setup-aegis-yabai.sh script manually

AEGIS_NOTIFY_SCRIPT="/usr/local/bin/aegis-yabai-notify"

# Create the notification script if it doesn't exist
if [ ! -f "$AEGIS_NOTIFY_SCRIPT" ]; then
    echo "Creating Aegis notification script..."
    sudo tee "$AEGIS_NOTIFY_SCRIPT" > /dev/null << 'SCRIPT'
#!/bin/bash
touch /tmp/aegis_yabai_event
SCRIPT
    sudo chmod +x "$AEGIS_NOTIFY_SCRIPT"
fi

# Remove old Aegis signals
yabai -m signal --remove aegis_space_changed 2>/dev/null
yabai -m signal --remove aegis_window_focused 2>/dev/null
yabai -m signal --remove aegis_window_created 2>/dev/null
yabai -m signal --remove aegis_window_destroyed 2>/dev/null
yabai -m signal --remove aegis_window_moved 2>/dev/null
yabai -m signal --remove aegis_application_front_switched 2>/dev/null

# Register Aegis signals
yabai -m signal --add event=space_changed action="$AEGIS_NOTIFY_SCRIPT" label=aegis_space_changed
yabai -m signal --add event=window_focused action="$AEGIS_NOTIFY_SCRIPT" label=aegis_window_focused
yabai -m signal --add event=window_created action="$AEGIS_NOTIFY_SCRIPT" label=aegis_window_created
yabai -m signal --add event=window_destroyed action="$AEGIS_NOTIFY_SCRIPT" label=aegis_window_destroyed
yabai -m signal --add event=window_moved action="$AEGIS_NOTIFY_SCRIPT" label=aegis_window_moved
yabai -m signal --add event=application_front_switched action="$AEGIS_NOTIFY_SCRIPT" label=aegis_application_front_switched

echo "Aegis yabai integration loaded"
