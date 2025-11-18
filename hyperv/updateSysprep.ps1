# Ensure script is running as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator."
    exit 1
}

# Function to schedule this script to resume after reboot
function Schedule-Resume {
    $scriptPath = $MyInvocation.MyCommand.Definition
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "SysprepPrepResume" -Action $action -Trigger $trigger -Principal $principal -Force
}

# Remove scheduled task if it exists (to avoid loops)
if (Get-ScheduledTask -TaskName "SysprepPrepResume" -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName "SysprepPrepResume" -Confirm:$false
}

# --- Ensure PSWindowsUpdate module is installed ---
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "Installing PSWindowsUpdate module..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
}
Import-Module PSWindowsUpdate

# --- Ensure SDelete is installed ---
$sdeleteExe = "sdelete64.exe"
$sdeletePath = Get-Command $sdeleteExe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if (-not $sdeletePath) {
    Write-Host "SDelete not found, installing via winget..."
    winget install --id Microsoft.Sysinternals.SDelete -e --accept-package-agreements --accept-source-agreements

    # Re-check after installation
    $sdeletePath = Get-Command $sdeleteExe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

# 1. Install all Windows Updates (auto-reboot if needed)
Get-WindowsUpdate -AcceptAll -Install -AutoReboot

# If a reboot is required, schedule resume and reboot
if ((Get-ComputerInfo).WindowsUpdateAutoRebootRequired -eq $true) {
    Schedule-Resume
    Restart-Computer -Force
    exit
}

# 2. Update all Winget apps
winget upgrade --all --silent
# 3. Run your aggressive debloat script
$debloatScript = "C:\Scripts\Win11Debloat.ps1"
if (Test-Path $debloatScript) {
    Write-Host "Running Win11Debloat script..."
    & $debloatScript
} else {
    Write-Host "Debloat script not found at $debloatScript"
}

# 4. Aggressive cleanup of Windows Update and temp files
Write-Host "Cleaning up Windows Update files..."
Remove-Item -Path 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Cleaning up temp directories..."
$TempPaths = @(
    $env:TEMP,
    $env:TMP,
    "C:\Windows\Temp",
    "C:\Users\*\AppData\Local\Temp"
)
foreach ($path in $TempPaths) {
    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 5. Run SDelete to zero free space
if ($sdeletePath) {
    Write-Host "Running SDelete from $sdeletePath..."
    Start-Process -Wait -FilePath $sdeletePath -ArgumentList "/accepteula", "-z C:"
} else {
    Write-Host "SDelete still not found. Please verify installation."
}

# 6. Shutdown VM (optional)
# Uncomment the next line if you want the VM to shut down automatically
Stop-Computer -Force
