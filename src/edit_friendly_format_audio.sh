#!/usr/bin/env bash
set -eou pipefail

# ==============================================
# edit_friendly_format_audio.sh
# ==============================================

# ==============================================
# Function to check for required dependencies.
# ==============================================
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

# ==============================================
# Function to select audio files.
# ==============================================
select_audio_files() {
    local selected_files

    for attempt in {1..3}; do
        selected_files=$(zenity --file-selection \
            --title="Select Audio File(s)" \
            --multiple \
            --file-filter='(mp3, aac, wav, flac, ogg, m4a) | *.mp3 *.aac *.wav *.flac *.ogg *.m4a' \
            --separator="|" \
            2>/dev/null)

        local retVal=$?

        if [ $retVal -eq 0 ] && [ -n "$selected_files" ]; then
            break
        fi

        if [ $retVal -eq 1 ]; then
            exit 0
        fi

        if [ $attempt -lt 3 ]; then
            zenity --warning \
                --title="File Selection Issue" \
                --text="There was an issue selecting files. Please try again." \
                --width=300
        fi
    done

    if [ -z "$selected_files" ]; then
        zenity --error \
            --title="File Selection Failed" \
            --text="Could not properly select audio files after multiple attempts.\nPlease try running the script again." \
            --width=300
        exit 1
    fi

    echo "$selected_files"
}

# ==============================================
# Function to select output folder.
# ==============================================
select_output_folder() {
    zenity --file-selection \
        --title="Select Output Folder" \
        --directory
}

# ==============================================
# Function to decide if transcoding is needed.
# Returns:
#   0 - Needs transcoding
#   1 - Skip transcoding
# ==============================================
needs_transcoding() {
    local input_file="$1"
    local output_file

    # Determine the output file path following the _edit_friendly_format.wav naming convention
    if [[ "$input_file" == *_edit_friendly_format.wav ]]; then
        # If input is already a _edit_friendly_format.wav file, use the same name
        output_file="${output_folder}/$(basename "$input_file")"
    else
        # For other files, append _edit_friendly_format.wav to the base name
        output_file="${output_folder}/$(basename "${input_file%.*}")_edit_friendly_format.wav"
    fi

    # Case 1: Input file already has _edit_friendly_format.wav extension
    if [[ "$input_file" == *_edit_friendly_format.wav ]]; then
        echo "# Skipping: Input file is already in _edit_friendly_format.wav format" >&2
        return 1  # Skip transcoding
    fi

    # Case 2: Check if output file already exists
    if [[ -f "$output_file" ]]; then
        echo "# Skipping: Output file already exists: $(basename "$output_file")" >&2
        return 1  # Skip transcoding
    fi

    # If neither condition is met, transcoding is needed
    return 0  # Needs transcoding
}

# ==============================================
# Transcoding function.
# ==============================================
transcode_files() {
    local input_files_str=$1
    local output_folder=$2
    local audio_codec="pcm_s24le"

    local FINAL_MESSAGE_DELAY=3

    # ==============================================
    # Temp files.
    # ==============================================
    local failed_tmpfile
    failed_tmpfile=$(mktemp) || {
        zenity --error --text="Failed to create temporary file"
        exit 1
    }

    local skipped_tmpfile
    skipped_tmpfile=$(mktemp) || {
        zenity --error --text="Failed to create temporary file for skipped files"
        rm "$failed_tmpfile"
        exit 1
    }

    local success_tmpfile
    success_tmpfile=$(mktemp) || {
        zenity --error --text="Failed to create temporary file for successful files"
        rm "$failed_tmpfile" "$skipped_tmpfile"
        exit 1
    }

    : > "$failed_tmpfile"
    : > "$skipped_tmpfile"
    : > "$success_tmpfile"
    # ==============================================

    IFS='|' read -r -a input_files <<< "$input_files_str"

    local total_files=${#input_files[@]}
    local current_file=0

    (
    for file in "${input_files[@]}"; do
        current_file=$((current_file + 1))
        filename=$(basename "$file")
        output_file="${output_folder}/${filename%.*}_edit_friendly_format.wav"

        mkdir -p "$output_folder"

        echo "# Transcoding audio file: $filename ($current_file of $total_files)"

        if [ $current_file -eq $total_files ]; then
            echo "99"
        else
            echo "$((current_file * 100 / total_files))"
        fi

        # ONLY CHANGE: Function now skips based on filename checks
        if needs_transcoding "$file" "$audio_codec"; then
            if ffmpeg -hide_banner -loglevel warning -i "$file" \
                -c:a "$audio_codec" -threads 0 \
                "$output_file" -y 2>/dev/null; then
                echo "${filename%.*}_edit_friendly_format.wav" >> "$success_tmpfile"
            else
                [ -f "$output_file" ] && rm "$output_file"
                echo "${filename}" >> "$failed_tmpfile"
            fi
        else
            echo "# Skipping existing file: $filename"
            echo "${filename}" >> "$skipped_tmpfile"

            if [ $current_file -eq $total_files ]; then
                echo "99"
            else
                echo "$((current_file * 100 / total_files))"
            fi
            continue
        fi

        if [ $current_file -eq $total_files ]; then
            echo "# Transcoding finishing..."
            sleep $FINAL_MESSAGE_DELAY
            echo "100"
        fi
    done
    ) | zenity --progress \
        --title="Transcoding Audio File(s)" \
        --text="Transcoding starting..." \
        --percentage=0 \
        --no-cancel \
        --auto-close \
        --width=600

    local failed_files=()
    local skipped_files=()
    local successful_files=()

    [ -s "$failed_tmpfile" ] && mapfile -t failed_files < "$failed_tmpfile"
    [ -s "$skipped_tmpfile" ] && mapfile -t skipped_files < "$skipped_tmpfile"
    [ -s "$success_tmpfile" ] && mapfile -t successful_files < "$success_tmpfile"

    rm "$failed_tmpfile" "$skipped_tmpfile" "$success_tmpfile"
    # =========================
    # Transcode summary.
    # =========================
    local message=""

    # Add Successful section if there are any
    if [[ ${#successful_files[@]} -gt 0 ]]; then
        message+="Edit Friendly Format:\n$(printf "%s\n" "${successful_files[@]/#/- }")"
    fi

    # Add Skipped section if any
    if [[ ${#skipped_files[@]} -gt 0 ]]; then
        [[ -n "$message" ]] && message+="\n\n"
        message+="Skipped:\n$(printf "%s\n" "${skipped_files[@]/#/- }")"
    fi

    # Add Failed section if any
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        [[ -n "$message" ]] && message+="\n\n"
        message+="Failed:\n$(printf "%s\n" "${failed_files[@]/#/- }")"
    fi

    # Determine icon
    local icon="info"
    [[ ${#failed_files[@]} -gt 0 ]] && icon="error"

    # Show notification
    zenity --notification \
        --icon="$icon" \
        --text="$message"
    }

# ==============================================
# Main function.
# ==============================================
main() {
    check_dependencies

    local input_files=$(select_audio_files)
    if [ -z "$input_files" ]; then
        exit 1
    fi

    local output_folder=$(select_output_folder)
    if [ -z "$output_folder" ]; then
        exit 1
    fi

    transcode_files "$input_files" "$output_folder"

    # Ask user if they want to view the output folder
    if zenity --question \
        --ellipsize \
        --title="Edit Friendly Format" \
        --text="Would you like to view the output folder?" \
        --width=400; then
        xdg-open "$output_folder"
    fi
}

main
