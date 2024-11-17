#!/bin/bash

# Function to check and install dependencies
install_dependencies() {
    echo "Checking dependencies..."

    # Install curl if not found
    if ! command -v curl &>/dev/null; then
        echo "Installing curl..."
        sudo apt-get update && sudo apt-get install -y curl
    fi

    # Install unzip if not found
    if ! command -v unzip &>/dev/null; then
        echo "Installing unzip..."
        sudo apt-get install -y unzip
    fi

    # Install Xray if not found
    if ! [ -f "./bin/xray" ]; then
        echo "Downloading Xray..."
        XRAY_VERSION="v1.8.1" # Specify the desired version
        XRAY_DIR="./bin"
        mkdir -p "$XRAY_DIR"

        # Download the Xray zip file and extract it
        XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/Xray-linux-64.zip"
        curl -L -o "$XRAY_DIR/xray.zip" "$XRAY_URL"

        unzip -o "$XRAY_DIR/xray.zip" -d "$XRAY_DIR"
        rm -f "$XRAY_DIR/xray.zip"
        echo "Xray installed in $XRAY_DIR."
    fi
}

# Install dependencies
install_dependencies

# set -euo pipefail
# IFS=$'\n\t'

# Define paths
BIN_DIR="bin"
TEMP_DIR="temp"
ZIP_FILE="$TEMP_DIR/downloaded.zip"
EXTRACT_DIR="$TEMP_DIR/extracted"
OUTPUT_CSV="results.csv"
VALIDIPS_CSV="ValidIPs.csv"
XRAY_EXECUTABLE="$BIN_DIR/xray"
XRAY_CONFIG_FILE="$BIN_DIR/config.json"
TEMP_CONFIG_FILE="$TEMP_DIR/temp_config.json"
fileSize=102400

# Ensure the temp and extracted directories exist
mkdir -p "$TEMP_DIR" "$EXTRACT_DIR"

# Check if an IP address is provided as an argument
if [ "$#" -gt 0 ]; then
    IPADDR="$1"
    echo "Checking IP: $IPADDR"

    # Check the IP over HTTP on port 443 (timeout after 3 seconds)
    HTTP_CHECK=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "http://$IPADDR:443")

    # If HTTP check returns "400", perform Xray check
    if [ "$HTTP_CHECK" == "400" ]; then
        echo "IP $IPADDR passed HTTP check. Starting Xray check..."

        # Base64-encode the IP address
        BASE64IP=$(echo -n "$IPADDR" | base64)

        # Update Xray config with the Base64 IP
        sed "s/PROXYIP/$BASE64IP/g" "$XRAY_CONFIG_FILE" >"$TEMP_CONFIG_FILE"

        # Start Xray as a background process with the updated config
        echo "Starting Xray for IP: $IPADDR"
        "$XRAY_EXECUTABLE" -config "$TEMP_CONFIG_FILE" &
        XRAY_PID=$!

        # Wait for Xray to initialize
        sleep 1

        # Check if Xray started successfully
        if ! ps -p $XRAY_PID >/dev/null; then
            echo "Failed to start Xray for IP: $IPADDR"
            echo "$IPADDR,$HTTP_CHECK,Failed to Start Xray" >>"$RESULTS_CSV"
            continue
        fi

        # Test 204 response with Xray
        XRAY_CHECK=$(curl -s -m 3 -o /dev/null -w "%{http_code}" --proxy http://127.0.0.1:8080 https://cp.cloudflare.com/generate_204)

        # Download Test
        curl -s -m 3 -w "TIME: %{time_total}" --proxy "http://127.0.0.1:8080" "https://speed.cloudflare.com/__down?bytes=$fileSize" --output "$TEMP_DIR/temp_downloaded_file" >"$TEMP_DIR/temp_output.txt"

        # Extract the download time from the output file
        downTimeMil=$(grep "TIME" "$TEMP_DIR/temp_output.txt" | awk -F': ' '{print $2}')
        downTimeMil=${downTimeMil:-0}

        # Check if the downloaded file size matches the requested size
        actualFileSize=$(stat -c%s "$TEMP_DIR/temp_downloaded_file" 2>/dev/null || echo 0)

        if [ "$actualFileSize" -eq "$fileSize" ]; then
            echo "Downloaded file size matches the requested size."
        else
            echo "Warning: Downloaded file size does not match the requested size."
        fi

        # Convert the floating-point download time to an integer (milliseconds)
        downTimeMilInt=$(printf "%.0f" "$(echo "$downTimeMil * 1000" | bc)")

        echo "Converted Download Time (ms): $downTimeMilInt"

        # Record result in CSV
        echo "IP: $IPADDR, HTTP Check: $HTTP_CHECK, 204 Check: $XRAY_CHECK, Download Time: $downTimeMilInt, File Size Match: $actualFileSize"
        echo "$IPADDR,$HTTP_CHECK,$XRAY_CHECK,$downTimeMilInt,$actualFileSize" >>"$OUTPUT_CSV"

        # Clean up temporary file
        rm -f "$TEMP_DIR/temp_downloaded_file"

        # Stop Xray process
        kill -9 $XRAY_PID
    fi
else
    # Download the ZIP file from the specified URL
    echo "Downloading ZIP file from https://zip.baipiao.eu.org..."
    curl -sLo "$ZIP_FILE" "https://zip.baipiao.eu.org"

    # Extract ZIP file to the extraction directory
    echo "Extracting ZIP file..."
    unzip -o "$ZIP_FILE" -d "$EXTRACT_DIR"

    # Create or clear the output CSV file
    echo "IP,HTTP Check,Xray Check,Download Time (ms),Download Size (Bytes)" >"$OUTPUT_CSV"

    # Loop through each file with "-443.txt" in the extraction directory
    for file in "$EXTRACT_DIR"/*-443.txt; do
        echo "Processing file: $file"

        while IFS= read -r IPADDR; do
            echo "Checking IP: $IPADDR"

            # Check the IP over HTTP on port 443 (timeout after 3 seconds)
            HTTP_CHECK=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "http://$IPADDR:443")

            if [ "$HTTP_CHECK" == "400" ]; then
                echo "IP $IPADDR passed HTTP check. Starting Xray check..."
                # Base64-encode the IP address
                BASE64IP=$(echo -n "$IPADDR" | base64)

                # Update Xray config with the Base64 IP
                sed "s/PROXYIP/$BASE64IP/g" "$XRAY_CONFIG_FILE" >"$TEMP_CONFIG_FILE"

                # Start Xray as a background process with the updated config
                echo "Starting Xray for IP: $IPADDR"
                "$XRAY_EXECUTABLE" -config "$TEMP_CONFIG_FILE" &
                XRAY_PID=$!
                sleep 1
                # Check if Xray started successfully
                if ! ps -p $XRAY_PID >/dev/null; then
                    echo "Failed to start Xray for IP: $IPADDR"
                    echo "$IPADDR,$HTTP_CHECK,Failed to Start Xray" >>"$RESULTS_CSV"
                    continue
                fi
                XRAY_CHECK=$(curl -s -m 3 -o /dev/null -w "%{http_code}" --proxy http://127.0.0.1:8080 https://cp.cloudflare.com/generate_204)

                # Check if XRAY_CHECK has a value (optional)
                if [ -n "$XRAY_CHECK" ]; then
                    echo "HTTP Status Code: $XRAY_CHECK"
                fi
                if [ "$XRAY_CHECK" == "204" ]; then
                    echo "204 Check Response is: $XRAY_CHECK"

                    # Download the file and capture the time taken using curl
                    curl -s -m 3 -w "TIME: %{time_total}\n" --proxy "http://127.0.0.1:8080" \
                        "https://speed.cloudflare.com/__down?bytes=$fileSize" \
                        --output "$TEMP_DIR/temp_downloaded_file" >"$TEMP_DIR/temp_output.txt"

                    # Extract the download time from the output file
                    downTimeMil=$(grep "TIME" "$TEMP_DIR/temp_output.txt" | awk -F': ' '{print $2}')
                    downTimeMil=${downTimeMil:-0}

                    # Get the actual size of the downloaded file
                    if [ -f "$TEMP_DIR/temp_downloaded_file" ]; then
                        actualFileSize=$(stat -c%s "$TEMP_DIR/temp_downloaded_file" 2>/dev/null || echo 0)
                    else
                        actualFileSize=0
                    fi

                    # Check if the actual size matches the expected size
                    if [ "$actualFileSize" -eq "$fileSize" ]; then
                        echo "$IPADDR" >>"$VALIDIPS_CSV"
                        echo "Download successful: $actualFileSize bytes"
                    else
                        echo "Download failed or incorrect size: $actualFileSize bytes (expected $fileSize bytes)"
                    fi

                    downTimeMilInt=$(printf "%.0f" "$(echo "$downTimeMil * 1000" | bc)")
                    echo "$IPADDR,$HTTP_CHECK,$XRAY_CHECK,$downTimeMilInt,$actualFileSize" >>"$OUTPUT_CSV"
                    rm -f "$TEMP_DIR/temp_downloaded_file"
                else
                    echo "$IPADDR,$HTTP_CHECK,$XRAY_CHECK,-,-" >>"$OUTPUT_CSV"
                fi

                kill -9 $XRAY_PID
            else
                echo "$IPADDR,$HTTP_CHECK,-,-,-" >>"$OUTPUT_CSV"

            fi
        done <"$file"
    done
    echo "Done. Results saved in $OUTPUT_CSV."
fi
