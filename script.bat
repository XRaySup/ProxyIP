@echo off
setlocal enabledelayedexpansion

:: Define paths
set "BIN_DIR=bin"
set "TEMP_DIR=temp"
set "ZIP_FILE=%TEMP_DIR%\downloaded.zip"
set "EXTRACT_DIR=%TEMP_DIR%\extracted"
set "OUTPUT_CSV=results.csv"
set "XRAY_EXECUTABLE=%BIN_DIR%\xray.exe"
set "XRAY_CONFIG_FILE=%BIN_DIR%\config.json"
set "TEMP_CONFIG_FILE=%TEMP_DIR%\temp_config.json"
set "CURL_OUTPUT=%TEMP_DIR%\_check.txt"

:: Ensure the temp and extracted directories exist
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"

:: Download the ZIP file from the specified URL
echo Downloading ZIP file from https://zip.baipiao.eu.org...
curl -sLo "%ZIP_FILE%" "https://zip.baipiao.eu.org"

:: Extract ZIP file to the extraction directory
echo Extracting ZIP file...
powershell -command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force"

:: Create or clear the output CSV file
echo IP,HTTP Check,Xray Check > "%OUTPUT_CSV%"

:: Loop through each file with "-443.txt" in the extraction directory
for %%f in ("%EXTRACT_DIR%\*-443.txt") do (
    echo Processing file: %%f

    :: Loop through each line (IP) in the file
    for /f "usebackq delims=" %%i in (%%f) do (
        set "IPADDR=%%i"
        echo Checking IP: !IPADDR!

        :: Check the IP over HTTP on port 443 (timeout after 3 seconds)
        for /f %%j in ('curl -s -m 3 -o nul -w "%%{http_code}" http://!IPADDR!:443') do set "HTTP_CHECK=%%j"

        :: If HTTP check returns "400", perform Xray check
        if "!HTTP_CHECK!"=="400" (
            echo IP !IPADDR! passed HTTP check. Starting Xray check...

            :: Encode IP in Base64 format
            for /f "tokens=*" %%k in ('powershell -command "[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('%IPADDR%'))"') do set "BASE64IP=%%k"

            :: Update the Xray config with the Base64 IP
            powershell -command "(Get-Content -Path '%XRAY_CONFIG_FILE%') -replace 'PROXYIP', '%BASE64IP%' | Set-Content -Path '%TEMP_CONFIG_FILE%'"

            :: Run Xray in the background and perform 204 check
            start "" /b "%XRAY_EXECUTABLE%" run -config "%TEMP_CONFIG_FILE%"
            timeout /t 5 /nobreak > nul

            :: Perform the 204 No Content check via Xray proxy
            for /f %%m in ('curl -s -o nul -w "%%{http_code}" --proxy http://127.0.0.1:8080 https://cp.cloudflare.com/generate_204') do set "XRAY_CHECK=%%m"

            :: Record result in CSV
            echo !IPADDR!,!HTTP_CHECK!,!XRAY_CHECK! >> "%OUTPUT_CSV%"

            :: Stop Xray process
            taskkill /f /im xray.exe > nul 2>&1
        ) else (
            :: Record failed HTTP check in CSV
            echo !IPADDR!,!HTTP_CHECK!,Skipped >> "%OUTPUT_CSV%"
        )
    )
)

:: Clean up temporary files if desired
:: Uncomment the next line to delete the temp folder after execution
:: rmdir /s /q "%TEMP_DIR%"

echo Done. Results saved in %OUTPUT_CSV%.
pause
