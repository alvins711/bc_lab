# ==========================================
# APACHE GUACAMOLE MANAGEMENT MODULE
# ==========================================

function Get-GuacAuthToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuacUrl,
        [Parameter(Mandatory = $true)]
        [string]$AdminUser,
        [Parameter(Mandatory = $true)]
        [string]$AdminPass
    )
    
    $AuthBody = @{
        username = $AdminUser
        password = $AdminPass
    }

    try {
        $AuthResponse = Invoke-RestMethod -Uri "$GuacUrl/api/tokens" -Method Post -ContentType "application/x-www-form-urlencoded" -Body $AuthBody -TimeoutSec 10
        return [PSCustomObject]@{
            Token      = $AuthResponse.authToken
            DataSource = $AuthResponse.dataSource
        }
    } catch {
        throw "Authentication failed or server unreachable: $($_.Exception.Message)"
    }
}

function New-GuacBulkUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuacUrl,
        [Parameter(Mandatory = $true)]
        [string]$AdminUser,
        [Parameter(Mandatory = $true)]
        [string]$AdminPass,
        [Parameter(Mandatory = $true)]
        [int]$UserCount,
        [string]$UserPrefix = "user",
        [string]$SharedPassword = "SameSecurePassword123!",
        [string]$ConnName = "Shared Server Auto-Login",
        [string]$ConnHost = "192.168.68.150",
        [string]$ConnPort = "22",
        [string]$ConnProtocol = "ssh"
    )

    Write-Host "Authenticating admin user..." -ForegroundColor Cyan
    try {
        $Auth = Get-GuacAuthToken -GuacUrl $GuacUrl -AdminUser $AdminUser -AdminPass $AdminPass
    } catch {
        Write-Error $_
        return
    }

    $Headers = @{ "Guacamole-Token" = $Auth.Token }
    $ds = $Auth.DataSource
    $tk = $Auth.Token
    Write-Host "Authenticated. Detected Data Source: $ds" -ForegroundColor Green

    # --- CREATE CONNECTION ---
    Write-Host "Creating target connection $ConnName..." -ForegroundColor Cyan
    
    $ConnObject = @{
        parentIdentifier = "ROOT"
        name             = $ConnName
        protocol         = $ConnProtocol
        attributes       = @{
            "max-connections"          = ""
            "max-connections-per-user" = ""
            "weight"                   = ""
            "failover-only"            = ""
            "guacd-port"               = ""
            "guacd-encryption"         = ""
            "guacd-hostname"           = ""
        }
        parameters       = @{
            hostname = $ConnHost
            port     = $ConnPort
            username = '${GUAC_USERNAME}'
            password = '${GUAC_PASSWORD}'
        }
    }
    $ConnPayload = $ConnObject | ConvertTo-Json -Depth 5

    try {
        $ConnResponse = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/connections?token=$tk" -Method Post -ContentType "application/json" -Body $ConnPayload -Headers $Headers
        $ConnId = $ConnResponse.identifier
        Write-Host "Connection created with ID: $ConnId" -ForegroundColor Green
    } catch {
        Write-Error "Failed to create connection. It may already exist: $_"
        return
    }

    # --- BULK USER CREATION LOOP ---
    Write-Host "Provisioning $UserCount users..." -ForegroundColor Cyan
    for ($i = 1; $i -le $UserCount; $i++) {
        $UserNum = if ($UserCount -lt 100) { $i.ToString("00") } else { $i.ToString("000") }
        $CurrentUser = "$UserPrefix$UserNum"

        $UserObject = @{
            username   = $CurrentUser
            password   = $SharedPassword
            attributes = @{
                disabled              = ""
                expired               = ""
                "access-window-start" = ""
                "access-window-end"   = ""
                "valid-from"          = ""
                "valid-until"         = ""
                timezone              = ""
            }
        }
        $UserPayload = $UserObject | ConvertTo-Json -Depth 5

        try {
            $null = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/users?token=$tk" -Method Post -ContentType "application/json" -Body $UserPayload -Headers $Headers
            Write-Host "   User [$CurrentUser] profile created." -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -match "409" -or $_.ErrorDetails.Message -match "ALREADY_EXISTS") {
                Write-Host "   User [$CurrentUser] already exists. Skipping creation..." -ForegroundColor Yellow
            } else {
                Write-Warning "   Failed to create user [$CurrentUser]. Skipping permissions mapping..."
                continue
            }
        }
        # --- LINK PERMISSIONS ---
        # Fixed: Removed the array wrap to match individual user resource schema rules
        $PermObject = @{
            op    = "add"
            path  = "/connectionPermissions/$ConnId"
            value = "READ"
        }
        $PermPayload = $PermObject | ConvertTo-Json

        try {
            $null = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/users/$CurrentUser/permissions?token=$tk" -Method Patch -ContentType "application/json" -Body $PermPayload -Headers $Headers
            Write-Host "      Permissions linked." -ForegroundColor Green
        } catch {
            Write-Warning "      Failed to link permissions for $CurrentUser."
        }

    }
    Write-Host "Provisioning process complete!" -ForegroundColor Green
}

function Remove-GuacBulkUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuacUrl,
        [Parameter(Mandatory = $true)]
        [string]$AdminUser,
        [Parameter(Mandatory = $true)]
        [string]$AdminPass,
        [Parameter(Mandatory = $true)]
        [int]$UserCount,
        [string]$UserPrefix = "user",
        [string]$ConnName = "Shared Server Auto-Login"
    )

    Write-Host "Authenticating admin user..." -ForegroundColor Cyan
    try {
        $Auth = Get-GuacAuthToken -GuacUrl $GuacUrl -AdminUser $AdminUser -AdminPass $AdminPass
    } catch {
        Write-Error $_
        return
    }

    $Headers = @{ "Guacamole-Token" = $Auth.Token }
    $ds = $Auth.DataSource
    $tk = $Auth.Token
    Write-Host "Authenticated. Detected Data Source: $ds" -ForegroundColor Green

    # --- BULK USER DELETION LOOP ---
    Write-Host "Deleting $UserCount users..." -ForegroundColor Cyan
    for ($i = 1; $i -le $UserCount; $i++) {
        $UserNum = if ($UserCount -lt 100) { $i.ToString("00") } else { $i.ToString("000") }
        $CurrentUser = "$UserPrefix$UserNum"

        try {
            $null = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/users/$CurrentUser?token=$tk" -Method Delete -Headers $Headers -TimeoutSec 5
            Write-Host "   Removed user [$CurrentUser]" -ForegroundColor Green
        } catch {
            Write-Host "   User [$CurrentUser] not found or already deleted." -ForegroundColor DarkGray
        }
    }

    # --- CLEANUP CONNECTION ---
    Write-Host "Locating connection target $ConnName..." -ForegroundColor Cyan
    try {
        $AllConnections = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/connections?token=$tk" -Method Get -Headers $Headers -TimeoutSec 5
        $TargetConn = $AllConnections.PSObject.Properties | Where-Object { $_.Value.name -eq $ConnName }

        if ($null -eq $TargetConn) {
            Write-Host "Connection $ConnName not found or already deleted." -ForegroundColor Yellow
        } else {
            $ConnId = $TargetConn.Value.identifier
            Write-Host "   Found Connection ID: $ConnId"
            
            # Terminate Active Sessions
            $ActiveSessions = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/activeConnections?token=$tk" -Method Get -Headers $Headers -TimeoutSec 5
            $StaleSessions = $ActiveSessions.PSObject.Properties | Where-Object { $_.Value.connectionIdentifier -eq $ConnId }
            
            if ($null -ne $StaleSessions) {
                foreach ($Session in $StaleSessions) {
                    $ActiveId = $Session.Name
                    Write-Host "   Dropping active session tunnel: $ActiveId..." -ForegroundColor Yellow
                    $DisconnectPayload = '[{"op":"remove","path":"/' + $ActiveId + '"}]'
                    $null = Invoke-RestMethod -Uri "$GuacUrl/api/session/data/$ds/activeConnections?token=$tk" -Method Patch -Headers $Headers -ContentType "application/json" -Body $DisconnectPayload -TimeoutSec 5
                }
                Start-Sleep -Seconds 1
            }

            Write-Host "   Deleting connection structure..." -ForegroundColor Yellow
            $null = Invoke-WebRequest -Uri "$GuacUrl/api/session/data/$ds/connections/$ConnId?token=$tk" -Method Delete -Headers $Headers -TimeoutSec 5
            Write-Host "Connection $ConnName successfully removed." -ForegroundColor Green
        }
    } catch {
        Write-Error "Error occurred clearing out connection layers: $_"
    }
    Write-Host "Cleanup process complete!" -ForegroundColor Green
}

# Export functions for global accessibility
Export-ModuleMember -Function Get-GuacAuthToken, New-GuacBulkUsers, Remove-GuacBulkUsers
