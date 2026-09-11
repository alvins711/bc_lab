# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script as an Administrator in PowerShell."
    Exit
}

# Prompt for the total number of users to remove
$UserCount = Read-Host "Enter the maximum user number to delete (e.g., 5 to clean up user01 through user05)"

# Validate input
if ($UserCount -match '^\d+$' -and [int]$UserCount -gt 0) {
    $UserCount = [int]$UserCount
} else {
    Write-Error "Error: Please enter a valid positive number."
    Exit
}

$MaxUserString = "user{0:d2}" -f $UserCount
Write-Warning "WARNING: This will permanently delete user01 to $MaxUserString and completely erase their profile directories."
$Confirm = Read-Host "Are you absolutely sure you want to proceed? (y/N)"

if ($Confirm -notmatch '^[Yy]$') {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    Exit
}

# Loop to remove users
for ($i = 1; $i -le $UserCount; $i++) {
    $Username = "user{0:d2}" -f $i

    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Host "User $Username does not exist. Skipping..." -ForegroundColor Yellow
    } else {
        Write-Host "Processing cleanup for $Username..." -ForegroundColor Cyan

        # 1. Forcefully disconnect the user if they have an active session
        $Session = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -match $Username }
        if ($Session) {
            # Use query session / logoff to terminate active user terminal sessions cleanly
            $SessionId = (quser $Username 2>$null | Select-String $Username) -replace '\s+', ' '
            if ($SessionId -match "$Username\s+(\S+)?\s+(\d+)\s+") {
                logoff $Matches[2] /v
                Start-Sleep -Seconds 2
            }
        }

        # 2. Delete the local Windows User Account
        Remove-LocalUser -Name $Username

        # 3. Completely delete the User Profile directory from disk
        $UserHome = "C:\Users\$Username"
        if (Test-Path $UserHome) {
            # Take ownership if files are locked down by system permissions, then remove recursively
            Remove-Item -Path $UserHome -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Successfully removed $Username and their profile contents." -ForegroundColor Green
    }
}

Write-Host "Done! Cleanup completed." -ForegroundColor Cyan

