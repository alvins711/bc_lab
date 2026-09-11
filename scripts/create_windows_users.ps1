# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script as an Administrator in PowerShell."
    Exit
}

# Prompt for the total number of users
$UserCount = Read-Host "Enter the number of users to create (e.g., 5 for user01 to user05)"

# Validate input
if ($UserCount -match '^\d+$' -and [int]$UserCount -gt 0) {
    $UserCount = [int]$UserCount
} else {
    Write-Error "Error: Please enter a valid positive number."
    Exit
}

# Prompt for shared password securely
$PasswordInput = Read-Host "Enter the shared password for all users" -AsSecureString

# Loop to create users
for ($i = 1; $i -le $UserCount; $i++) {
    # Pad number with a leading zero (e.g., user01)
    $Username = "user{0:d2}" -f $i

    # Check if user already exists
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
        Write-Host "User $Username already exists. Skipping..." -ForegroundColor Yellow
    } else {
        # Create the local user account
        New-LocalUser -Name $Username -Password $PasswordInput -Description "Bulk created user account" -FullName $Username | Out-Null
        
        # Add user to the standard Users group (removes them from any default administrative holds)
        Add-LocalGroupMember -Group "Users" -Member $Username | Out-Null

        Write-Host "User $Username created successfully." -ForegroundColor Green

        # -------------------------------------------------------------
        # CUSTOM PROFILE (EQUIVALENT TO PER-USER .BASHRC)
        # -------------------------------------------------------------
        # Windows requires the profile directory structure to exist. 
        # We pre-create the PowerShell profile path inside their future home directory.
        $UserHome = "C:\Users\$Username"
        $ProfileDir = "$UserHome\Documents\WindowsPowerShell"
        
        # Force create the directory structure
        New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
        
        # Define the profile content (your custom aliases/functions)
        $ProfileContent = @"
# --- Custom Settings Added by Admin Script ---
# Custom Aliases
Set-Alias -Name ll -Value Get-ChildItem
function cd-up { cd .. }
Set-Alias -Name .. -Value cd-up

# Custom Environment Variables
`$env:EDITOR = "notepad.exe"
`$env:USER_NICKNAME = "Nick-$Username"
"@

        # Write the profile script out to their directory
        $ProfilePath = "$ProfileDir\Microsoft.PowerShell_profile.ps1"
        Set-Content -Path $ProfilePath -Value $ProfileContent

        # Grant the specific user full ownership rights over their profile folder
        $Acl = Get-Acl $UserHome
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $UserHome $Acl
    }
}

Write-Host "Done! Created users up to user$( "{0:d2}" -f $UserCount )." -ForegroundColor Cyan

