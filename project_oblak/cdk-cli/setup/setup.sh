#!/usr/bin/env bash

TARGET_DIR="$(cd "$(dirname "$0")/../linux" && pwd)"

CURRENT_SHELL=$(basename "$SHELL")

case "$CURRENT_SHELL" in
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    bash)
        RC_FILE="$HOME/.bashrc"
        ;;
    *)
        RC_FILE="$HOME/.profile"
        ;;
esac

EXPORT_LINE="export PATH=\"$TARGET_DIR:\$PATH\""

if [ -f "$RC_FILE" ] && grep -Fxq "$EXPORT_LINE" "$RC_FILE"; then
    echo "Path is already added to $RC_FILE"
else
    echo "$EXPORT_LINE" >> "$RC_FILE"
    echo "Added: $TARGET_DIR in PATH inside $RC_FILE"
    echo "Run: 'source $RC_FILE' or restart your terminal to apply changes."
fi