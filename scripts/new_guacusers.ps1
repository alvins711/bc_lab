# ==========================================
# CONFIGURATION - UPDATE THESE FOR YOUR ENV
# ==========================================
$GuacUrl      = "https://localhost"
$AdminUser    = "guacadmin"
$AdminPass    = "guacadmin"

# Base User Configuration
$UserPrefix   = "user"
$SharedPassword = "user123"

# Connection Details
$ConnName     = "Shared Server Auto-Login"
$ConnProtocol = "ssh"
$ConnHost     = "claude_workspace"
$ConnPort     = "22"

# ==========================================
# INTERACTIVE USER PROMPT
# ==========================================
Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Apache Guacamole Bulk User Provisioning    " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$UserCount = 0
while ($UserCount -le 0) {
    [string]$InputCount = Read-Host "How many users would you like to create? (e.g., 10)"
    if ($InputCount -match '^[0-9]+$' -and [int]$InputCount -gt 0) {
        $UserCount = [int]$InputCount
    } else {
        Write-Host "❌ Invalid input. Please enter a positive integer." -ForegroundColor Red
    }
}

Write-Host "`n🚀 Preparing to execute provisioning loops..." -ForegroundColor Yellow
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
    Write-Host "❌ Authentication failed or server unreachable! Details:" -ForegroundColor Red
    Write-Error $_
    Exit
}

Write-Host "✅ Authenticated successfully. Detected Data Source: $DataSource"

# ==========================================
# 2. CREATE THE AUTO-INJECT CONNECTION
# ==========================================
Write-Host "Creating target connection '$ConnName'..."

# PowerShell multi-line string using Here-String
$ConnPayload = @"
{
    "parentIdentifier": "ROOT",
    "name": "$ConnName",
    "protocol": "$ConnProtocol",
    "attributes": {
        "max-connections": "",
        "max-connections-per-user": "",
        "weight": "",
        "failover-only": "",
        "guacd-port": "",
        "guacd-encryption": "",
        "guacd-hostname": ""
    },
    "parameters": {
        "hostname": "$ConnHost",
        "port": "$ConnPort",
        "username": "`${GUAC_USERNAME}",
        "password": "`${GUAC_PASSWORD}"
    }
}
"@

try {
    $ConnResponse = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/connections?token=$AuthToken" -Method Post -ContentType "application/json" -Body $ConnPayload
    $ConnId       = $ConnResponse.identifier
    Write-Host "✅ Connection created with ID: $ConnId" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create connection. The structure might already exist." -ForegroundColor Red
    Write-Error $_
    Exit
}

Write-Host "------------------------------------------------"

# ==========================================
# 3. BULK USER CREATION LOOP
# ==========================================
Write-Host "Starting creation of $UserCount users..."

for ($i = 1; $i -le $UserCount; $i++) {
    # Match the sequential zero padding logic
    if ($UserCount -lt 100) {
        $UserNum = $i.ToString("00")
    } else {
        $UserNum = $i.ToString("000")
    }
    
    $CurrentUser = "$UserPrefix$UserNum"
    Write-Host "Processing [$CurrentUser]..." -ForegroundColor Yellow

    $UserPayload = @"
{
    "username": "$CurrentUser",
    "password": "$SharedPassword",
    "attributes": {
        "disabled": "",
        "expired": "",
        "access-window-start": "",
        "access-window-end": "",
        "valid-from": "",
        "valid-until": "",
        "timezone": ""
    }
}
"@

    try {
        $UserResponse = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/users?token=$AuthToken" -Method Post -ContentType "application/json" -Body $UserPayload
        Write-Host "   ✅ Profile created." -ForegroundColor Green
    } catch {
        # Check if the error returned points to a duplicate record
        if ($_.Exception.Message -match "409" -or $_.ErrorDetails.Message -match "ALREADY_EXISTS") {
            Write-Host "   ⚠️ User already exists. Transitioning straight to connection pairing..." -ForegroundColor Weak
        } else {
            Write-Host "   ❌ Failed to create user profile. Skipping." -ForegroundColor Red
            continue
        }
    }

    # Assign connection access tracking block
    $PermPayload = @"
[
    {
        "op": "add",
        "path": "/connectionPermissions/$ConnId",
        "value": "READ"
    }
]
"@

    try {
        $PermResponse = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$DataSource/users/$CurrentUser/permissions?token=$AuthToken" -Method Patch -ContentType "application/json" -Body $PermPayload
        Write-Host "   ✅ Connection permission linked." -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Failed to map connection permissions." -ForegroundColor Red
    }
}

Write-Host "------------------------------------------------"
Write-Host "🎉 Bulk user provisioning successfully complete!" -ForegroundColor Green

