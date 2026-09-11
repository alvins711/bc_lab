# ==========================================
# CONFIGURATION - MUST MATCH THE CREATION SCRIPT
# ==========================================
$GuacUrl    = "http://192.168.68.102:8081/guacamole"
$AdminUser  = "guacadmin"
$AdminPass  = "guacadmin"

$UserPrefix = "user"     
$ConnName   = "Shared Server Auto-Login"

# ==========================================
# INTERACTIVE USER PROMPT
# ==========================================
Clear-Host
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host "  Apache Guacamole Automated Cleanup Tool    " -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""

$UserCount = 0
while ($UserCount -le 0) {
    [string]$InputCount = Read-Host "How many sequential users do you need to remove? (e.g., 10)"
    if ($InputCount -match '^[0-9]+$' -and [int]$InputCount -gt 0) {
        $UserCount = [int]$InputCount
    } else {
        Write-Host "❌ Invalid input. Please enter a positive integer." -ForegroundColor Red
    }
}

Write-Host "`n🧹 Preparing to purge $UserCount users and connection profiles..." -ForegroundColor Red
Write-Host "------------------------------------------------"

# ==========================================
# 1. AUTHENTICATE & GET TOKEN
# ==========================================
Write-Host "Authenticating admin user..."

$AuthBody = @{
    username = $AdminUser
    password = $AdminPass
}

try {
    $AuthResponse = Invoke-RestMethod -Uri "$GuacUrl/api/tokens" -Method Post -ContentType "application/x-www-form-urlencoded" -Body $AuthBody -TimeoutSec 10
    $AuthToken    = $AuthResponse.authToken
    $DataSource   = $AuthResponse.dataSource
} catch {
    Write-Host "❌ Connection error or failed validation!" -ForegroundColor Red
    Exit
}

Write-Host "✅ Authenticated. Detected Data Source: $DataSource"
Write-Host "------------------------------------------------"

# Define standard headers to re-use for all database operations
$Headers = @{
    "Guacamole-Token" = $AuthToken
}

# ==========================================
# 2. BULK USER DELETION LOOP
# ==========================================
Write-Host "Starting removal of $UserCount users..."

for ($i = 1; $i -le $UserCount; $i++) {
    if ($UserCount -lt 100) {
        $UserNum = $i.ToString("00")
    } else {
        $UserNum = $i.ToString("000")
    }
    
    $CurrentUser = "$UserPrefix$UserNum"
    Write-Host "Processing [$CurrentUser]..." -ForegroundColor Yellow

    try {
        Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/users/$CurrentUser" -Method Delete -Headers $Headers -TimeoutSec 5
        Write-Host "   ✅ User successfully removed." -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️ User not found or already gone. Skipping." -ForegroundColor DarkGray
    }
}

Write-Host "------------------------------------------------"

# ==========================================
# 3. LOCATE & REMOVE THE TARGET CONNECTION
# ==========================================
Write-Host "Searching for connection identifier matching '$ConnName'..."

try {
    # Fetch map with matching authentication headers
    $AllConnections = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/connections" -Method Get -Headers $Headers -TimeoutSec 5
    $TargetConn = $AllConnections.PSObject.Properties | Where-Object { $_.Value.name -eq $ConnName }

    if ($null -eq $TargetConn) {
        Write-Host "⚠️ Connection '$ConnName' not found or already deleted." -ForegroundColor Yellow
    } else {
        $ConnId = $TargetConn.Value.identifier
        Write-Host "Found connection identifier: $ConnId"
        
        # --- TERMINATE ACTIVE SESSIONS ---
        Write-Host "Checking for active sessions holding this connection open..."
        $ActiveSessions = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/activeConnections" -Method Get -Headers $Headers -TimeoutSec 5
        $StaleSessions = $ActiveSessions.PSObject.Properties | Where-Object { $_.Value.connectionIdentifier -eq $ConnId }
        
        if ($null -ne $StaleSessions) {
            foreach ($Session in $StaleSessions) {
                $ActiveId = $Session.Name
                Write-Host "   ⚠️ Terminating active user tunnel session: $ActiveId..." -ForegroundColor Yellow
                
                $DisconnectPayload = '[{"op":"remove","path":"/' + $ActiveId + '"}]'
                Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/activeConnections" -Method Patch -Headers $Headers -ContentType "application/json" -Body $DisconnectPayload -TimeoutSec 5
            }
            Start-Sleep -Seconds 1
        }

        # --- PURGE THE TARGET CONNECTION ---
        Write-Host "Deleting connection..."
        
        # Completely decoupled URL query parameters from explicit headers block
        $DeleteResponse = Invoke-WebRequest -Uri "$GuacUrl/api/session/data/$DataSource/connections/$ConnId" -Method Delete -Headers $Headers -TimeoutSec 5
        
        Write-Host "✅ Connection '$ConnName' successfully removed." -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Errored out searching or altering connection tree data layers." -ForegroundColor Red
    
    # Advanced verification logging to reveal the exact HTTP error code if it fails
    if ($_.Exception.Response) {
        $StatusCode = [int]$_.Exception.Response.StatusCode
        $Reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $ResponseText = $Reader.ReadToEnd()
        Write-Host "   HTTP Status Code: $StatusCode" -ForegroundColor Red
        Write-Host "   API Response Text: $ResponseText" -ForegroundColor DarkRed
    } else {
        Write-Host "   Error Message: $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

Write-Host "------------------------------------------------"
Write-Host "🎉 Cleanup process completed!" -ForegroundColor Green
