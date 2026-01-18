#!/usr/bin/env sh

# ============================================
# Aegis Integration for .yabairc
# ============================================
# Add this section to your ~/.yabairc file to automatically
# set up Aegis integration when yabai starts
#
# OR run the setup-aegis-yabai.sh script manually

# AEGIS_INTEGRATION_START
# Aegis window manager integration - DO NOT EDIT THIS SECTION
AEGIS_NOTIFY="$HOME/.config/aegis/aegis-yabai-notify"

# Remove old signals (ignore errors if they don't exist)
yabai -m signal --remove aegis_space_changed 2>/dev/null || true
yabai -m signal --remove aegis_space_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_focused 2>/dev/null || true
yabai -m signal --remove aegis_window_created 2>/dev/null || true
yabai -m signal --remove aegis_window_destroyed 2>/dev/null || true
yabai -m signal --remove aegis_window_moved 2>/dev/null || true
yabai -m signal --remove aegis_application_front_switched 2>/dev/null || true

# Register Aegis signals with YABAI_EVENT_TYPE environment variable
yabai -m signal --add event=space_changed action="YABAI_EVENT_TYPE=space_changed $AEGIS_NOTIFY" label=aegis_space_changed
yabai -m signal --add event=space_destroyed action="YABAI_EVENT_TYPE=space_destroyed $AEGIS_NOTIFY" label=aegis_space_destroyed
yabai -m signal --add event=window_focused action="YABAI_EVENT_TYPE=window_focused $AEGIS_NOTIFY" label=aegis_window_focused
yabai -m signal --add event=window_created action="YABAI_EVENT_TYPE=window_created $AEGIS_NOTIFY" label=aegis_window_created
yabai -m signal --add event=window_destroyed action="YABAI_EVENT_TYPE=window_destroyed $AEGIS_NOTIFY" label=aegis_window_destroyed
yabai -m signal --add event=window_moved action="YABAI_EVENT_TYPE=window_moved $AEGIS_NOTIFY" label=aegis_window_moved
yabai -m signal --add event=application_front_switched action="YABAI_EVENT_TYPE=application_front_switched $AEGIS_NOTIFY" label=aegis_application_front_switched
# AEGIS_INTEGRATION_END

echo "Aegis yabai integration loaded"
