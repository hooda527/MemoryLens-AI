$ProgressPreference = 'SilentlyContinue'
$url = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.6-stable.zip'
$zip = 'C:\Users\hooda\flutter.zip'
$dest = 'C:\Users\hooda'

try {
    Write-Host "Starting download..."
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600
    $size = (Get-Item $zip).Length
    Write-Host "Download complete. Size: $size bytes"
    Write-Host "Extracting..."
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    Write-Host "Extraction complete."
    Remove-Item $zip
    Write-Host "Done! Flutter SDK is at C:\Users\hooda\flutter"
    Get-ChildItem 'C:\Users\hooda\flutter' | Select-Object -First 5
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
}
