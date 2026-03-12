# Dropbox Authentication Utility for RokuCalendar
# This script helps you get a permanent refresh token for your Dropbox account.

$clientId = "YOUR_DROPBOX_APP_KEY"
$clientSecret = "YOUR_DROPBOX_APP_SECRET"
$authUrl = "https://www.dropbox.com/oauth2/authorize?client_id=$clientId&response_type=code&token_access_type=offline"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " RokuCalendar: Dropbox Setup" -ForegroundColor Cyan
Write-Host "====================================================="
Write-Host "1. Opening your browser to the Dropbox login page..."
Start-Process $authUrl

Write-Host ""
$code = Read-Host "2. After logging in and clicking 'Allow', copy the code provided by Dropbox and paste it here"

if ([string]::IsNullOrWhiteSpace($code)) {
    Write-Host "No code entered. Exiting." -ForegroundColor Red
    exit
}

Write-Host "`nExchanging code for permanent access token..."
$body = @{
    code = $code.Trim()
    grant_type = 'authorization_code'
    client_id = $clientId
    client_secret = $clientSecret
}

try {
    $response = Invoke-RestMethod -Uri 'https://api.dropboxapi.com/oauth2/token' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    
    if ($response.refresh_token) {
        $refreshToken = $response.refresh_token
        Write-Host "Success! Permanent refresh token acquired." -ForegroundColor Green
        
        $configPath = "source/config.brs"
        if (-not (Test-Path $configPath)) {
            Write-Host "Creating source/config.brs from template..." -ForegroundColor Gray
            Copy-Item "source/config.brs.template" $configPath
        }

        $configContent = Get-Content $configPath -Raw
        if ($configContent -match '"refreshToken":') {
            $configContent = $configContent -replace '"refreshToken": ".*?"', "`"refreshToken`": `"$refreshToken`""
        } else {
            $configContent = $configContent -replace '("appSecret": ".*?",?)', "`$1`n            `"refreshToken`": `"$refreshToken`","
        }
        
        Set-Content $configPath $configContent -NoNewline
        Write-Host "Token securely saved to source/config.brs!" -ForegroundColor Green
        Write-Host "`nYou can now deploy the app to your Roku." -ForegroundColor Cyan
    } else {
        Write-Host "Exchange successful, but no refresh token was returned. Ensure you haven't used this code already." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error exchanging code. Ensure the code is correct and hasn't expired (5 min limit)." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
Write-Host ""
Pause
