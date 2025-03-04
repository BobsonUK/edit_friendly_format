#!/usr/bin/env bash
# Enable strict error handling
set -eou pipefail

# edit_friendly_format_main.sh

# Function to check required dependencies
check_dependencies() {
    if ! command -v zenity &> /dev/null; then
        printf "Error: zenity must be installed first.\n"
        printf "Install with your package manager.\n"
        exit 1
    fi

    if ! command -v ffmpeg &> /dev/null; then
        printf "Error: ffmpeg must be installed first.\n"
        printf "Install with your package manager.\n"
        zenity --error \
                --text="Error: ffmpeg must be installed first.\nInstall with your package manager.\n"
        exit 1
    fi
}

welcome_menu() {
    choice=$(zenity --question \
        --title="Edit Friendly Format" \
        --text="What type of file(s) would you like to make edit_friendly_format today?" \
        --switch \
        --width=650 \
        --extra-button "Audio" \
        --extra-button "Video" \
        2>/dev/null)  # Suppress zenity warnings

    echo "$choice"  # Output the choice
}

# Main function
main() {
    check_dependencies

    choice=$(welcome_menu)

    case "$choice" in
        "Audio")
            /app/bin/edit_friendly_format_audio.sh
            ;;
        "Video")
            /app/bin/edit_friendly_format_video.sh
            ;;
        "")
            exit 0  # Cancel button pressed
            ;;
        *)
            zenity --error --text="Please select Audio or Video using the buttons." --title="Error"
            exit 1
            ;;
    esac
}

# Execute main function
main
