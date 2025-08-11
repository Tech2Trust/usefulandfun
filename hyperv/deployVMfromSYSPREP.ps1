# Define paths and names
$hypervPath = "C:\HyperV"
$sysprepPath = "$hypervPath\VM-W11-SYSPREP"
$sysprepName = "VM-W11-SYSPREP"
$logPath = "$hypervPath\SysPrepExportImport.log"
$vmNames = @("VM-W11-SBX-01", "VM-W11-SBX-02")

# Function to write to log
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $message"
    Add-Content -Path $logPath -Value $entry
    Write-Host $message
}

# Function to remove a VM and clear its folder
function Remove-VMAndClearFolder {
    param (
        [string]$vmName,
        [string]$vmPath
    )

    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Stop-VM -Name $vmName -Force
        Remove-VM -Name $vmName -Force
        Write-Log "Removed VM: $vmName"
    }

    if (Test-Path $vmPath) {
        Remove-Item -Path "$vmPath\*" -Recurse -Force
        Write-Log "Cleared folder: $vmPath"
    }
}

# Function to import and configure a new VM
function Import-NewVM {
    param (
        [string]$sourcePath,
        [string]$targetPath,
        [string]$vmName
    )

    try {
        # Import the VM from SYSPREP folder
        $importedVM = Import-VM -Path $sourcePath -Copy -GenerateNewId -VhdDestinationPath $targetPath -VirtualMachinePath $targetPath -SnapshotFilePath $targetPath -SmartPagingFilePath $targetPath
        Rename-VM -VM $importedVM -NewName $vmName
        Write-Log "Imported and renamed VM to: $vmName"

        # Rename the VHDX file
        $vhdx = Get-ChildItem -Path $targetPath -Filter *.vhdx | Select-Object -First 1
        if ($vhdx) {
            $newVhdxName = "$vmName.vhdx"
            Rename-Item -Path $vhdx.FullName -NewName $newVhdxName
            Write-Log "Renamed VHDX to: $newVhdxName"

            Set-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -Path "$targetPath\$newVhdxName"
            Write-Log "Updated VM configuration to use new VHDX file"
        }

        # Start the VM
        Start-VM -Name $vmName
        Write-Log "Started VM: $vmName"
    }
    catch {
        Write-Log "ERROR processing ${vmName}: $($_)"
    }
}

# Start logging
Write-Log "=== Script started ==="

# Remove existing VMs and clear folders
foreach ($vmName in $vmNames) {
    $vmPath = "$hypervPath\$vmName"
    Remove-VMAndClearFolder -vmName $vmName -vmPath $vmPath
}

# Import new VMs
foreach ($vmName in $vmNames) {
    $vmPath = "$hypervPath\$vmName"
    Import-NewVM -sourcePath $sysprepPath -targetPath $vmPath -vmName $vmName
}

Write-Log "=== Script completed successfully ==="
