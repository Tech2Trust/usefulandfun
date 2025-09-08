# Define constants
$hypervPath = "C:\HyperV"
$sysprepPath = Join-Path $hypervPath "VM-W11-SYSPREP"
$vmSwitchName = "IsolatedInternal"  # Change this per host
$vmNames = @("VM-W11-SBX-01", "VM-W11-SBX-02")
$memoryStartupBytes = 2GB

# Logging function
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $message"
    Write-Host $entry
}

# Create new VM from SYSPREP VHDX
function Create-NewVMFromSysprep {
    param (
        [string]$vmName,
        [string]$sysprepVhdxPath,
        [string]$targetPath
    )

    # Remove existing VM if it exists
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Stop-VM -Name $vmName -Force
        Remove-VM -Name $vmName -Force
        Write-Log "Removed existing VM: $vmName"
    }

    # Prepare target folder
    if (Test-Path $targetPath) {
        Remove-Item -Path "$targetPath\*" -Recurse -Force
        Write-Log "Cleared folder: $targetPath"
    } else {
        New-Item -Path $targetPath -ItemType Directory | Out-Null
        Write-Log "Created folder: $targetPath"
    }

    # Copy and rename VHDX
    $newVhdxPath = Join-Path $targetPath "$vmName.vhdx"
    Copy-Item -Path $sysprepVhdxPath -Destination $newVhdxPath
    Write-Log "Copied SYSPREP VHDX to: $newVhdxPath"

    # Create new VM
    New-VM -Name $vmName -MemoryStartupBytes $memoryStartupBytes -Generation 2 -Path $targetPath | Out-Null
    Add-VMScsiController -VMName $vmName
    Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -Path $newVhdxPath
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows"

    # Connect to virtual switch
    Connect-VMNetworkAdapter -VMName $vmName -SwitchName $vmSwitchName
    Write-Log "Connected VM '$vmName' to switch '$vmSwitchName'"

    # Start the VM
    Start-VM -Name $vmName
    Write-Log "Started VM: $vmName"
}

# Get SYSPREP VHDX
$sysprepVhdx = Get-ChildItem -Path $sysprepPath -Filter *.vhdx | Select-Object -First 1
if (-not $sysprepVhdx) {
    Write-Log "ERROR: No SYSPREP VHDX found in $sysprepPath"
    exit
}

# Create VMs
foreach ($vmName in $vmNames) {
    $targetPath = Join-Path $hypervPath $vmName
    Create-NewVMFromSysprep -vmName $vmName -sysprepVhdxPath $sysprepVhdx.FullName -targetPath $targetPath
}

Write-Log "=== All VMs created successfully ==="
