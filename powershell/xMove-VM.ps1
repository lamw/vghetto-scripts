<#
.SYNOPSIS
    Supports cross vCenter vMotion without shared SSO
.DESCRIPTION
   This script demonstrates an xVC-vMotion where a running Virtual Machine
   is live migrated between two vCenter Servers which are NOT part of the
   same SSO Domain which is only available using the vSphere 6.0 API.

   This script also supports live migrating a running Virtual Machine between
   two vCenter Servers that ARE part of the same SSO Domain (aka Enhanced Linked Mode)

   This script also supports migrating VMs connected to both a VSS/VDS as well as having multiple vNICs

   This script also supports migrating VMs having multiple disks and specifying different destination datastores.

   This script also supports migrating to/from VMware Cloud on AWS (VMC)

.EXAMPLE
    xMove-VM -VMName myVM -SourceVC $srcVC -DestVC $destVC -DestCred (Get-Credential) -Cluster myCluster -ResourcePool myPool -VMHost esxi1.local -Folder $DestFolder -Datastore ds1,ds2 -VMNetwork nw1,nw2

    Moves a VM with 2 NICs and 2 hard disks on two different datastores between vCenters.

    Setup:
    $srcVC = Connect-VIServer srcVC.local
    $destVC = Connect-VIServer destVC.local
    $DestFolder = get-item 'vis:\destVC.local@443\DC\vm\MyFoldler'

.EXAMPLE
    $xMoveParams = @{
        SourceVC = $srcVCName
        DestVC = $destVCName
        DestCred = $DestCred
        Cluster = 'MyCluster'
        Folder = Get-Folder "MyFolder"
        ResourcePool = 'Production'
        VMHost = 'esxi.local'
        Datastore = @('ds1','ds2')
        VMNetwork = @('nw1','nw2')
    }
    xMove-VM @ToP1xMoveParams -VMName dbb-migrationTest

    Use splatting to specify parameters more easily.

.NOTES
   File Name  : xMove-VM.ps1
   Author     : William Lam - @lamw
   Version    : 1.0

   Updated by  : Askar Kopbayev - @akopbayev
   Version     : 1.1
   Description : The script allows to run compute-only xVC-vMotion when the source VM has multiple disks on differnet datastores.

   Updated by  : William Lam - @lamw
   Version     : 1.2
   Description : Added additional parameters to be able to perform cold migration to/from VMware Cloud on AWS (VMC)
                 -ResourcePool
                 -uppercaseuuid

    Updated by  : dbaileyut
    Version     : 1.3
    Descriptoin : Revised parameters to fit PowerShell conventions better
                  - Helps av

.LINK
    http://www.virtuallyghetto.com/2016/05/automating-cross-vcenter-vmotion-xvc-vmotion-between-the-same-different-sso-domain.html
.LINK
   https://github.com/lamw

.INPUTS
   System.String[]
    You can pipe the VM names to the function.

.OUTPUTS
   Console output
#>
Function xMove-VM {
    #Requires -Modules @{ModuleName="VMware.VimAutomation.Core"; ModuleVersion="6.0"}
    param(
        # Name of the VM to migrate
        [Parameter(Mandatory=$true,
                   Position=0,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        [Alias('VM')]
        [String]$VMName,
        <# 
            Source vCenter server. If it is not connected, Connect-VIServer will
            be run.
        #>
        [Parameter(Mandatory=$true,
                   Position=1,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        $SourceVC,
        <# 
            Destination vCenter server. If it is not connected, Connect-VIServer will
            be run.
        #>
        [Parameter(Mandatory=$true,
                   Position=2,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        $DestVC,
        # Destination vCenter credentials
        [Parameter(Mandatory=$true,
                   Position=3,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        [Alias('Credential')]
        [pscredential]$DestCred,
        <#
            Destination resource pool. If the name is not unique in
            vCenter, specify a cluster or run Get-Resource pool to 
            assign this to a variable.
        #>
        [Parameter(Mandatory=$true,
                   Position=4,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        $ResourcePool,
        # Destination ESXi host name
        [Parameter(Mandatory=$true,
                   Position=5,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        [String]$VMHost,
        <#
            Destination datastore(s). If multiple datastores are specified, 
            each disk will be assigned to the datastores specified in order. 
            Otherwise, all disk will move to a single datastore.
        #>
        [Parameter(Mandatory=$true,
                   Position=6,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        [String[]]$Datastore,
        # Destination port group name(s) in order of network adapters
        [Parameter(Mandatory=$true,
                   Position=7,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        [String[]]$VMNetwork,
        # Destination cluster
        [Parameter(Mandatory=$false,
                   Position=8,
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromRemainingArguments=$false)]
        [String]$Cluster,
        <#
            Destination vCenter VM folder. If the name is not unique, 
            assign it to a variable using Get-Folder and picking the correct one 
            or use Get-Item and the vis:\ PSDrive to get the folder via its path.
        #>
        [Parameter(Mandatory=$false,
                    Position=9,
                    ValueFromPipeline=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false)]
        $Folder,
        # Only migrate the compute if the storage is shared
        [switch]$ComputeOnly,
        # Use the given vCenter UUID without forcing to upper case
        [switch]$LowerCaseUUID,
        <#
            Specifies that the destination port groups are on a Virtual Standard Switch (VSS) 
            instead of Virtual Distributed Switch (VDS)
        #>
        [switch]$StandardSwitch,
        # Run asynchronously, does not wait for the task to finish
        [switch]$Async
    )

    function Get-VCObject ($VC) {
        if ($VC -is [VMware.VimAutomation.ViCore.Util10.VersionedObjectImpl]) {
            return $VC
        } elseif ($global:DefaultVIServers.Name -contains "$VC") {
            return $global:DefaultVIServers | ? {$_.Name -eq "$VC"}
        } else {
            return Connect-VIServer "$VC"
        }
    }

    $SourceVCObj = Get-VCObject $SourceVC
    if ($SourceVCObj -isnot [VMware.VimAutomation.ViCore.Util10.VersionedObjectImpl]) {
        Write-Error "Could not get source vCenter connection for `"$SourceVC`""
        return
    }
    $DestVCObj = Get-VCObject $DestVC
    if ($DestVCObj -isnot [VMware.VimAutomation.ViCore.Util10.VersionedObjectImpl]) {
        Write-Error "Could not get destination vCenter connection for `"$DestVCObj`""
        return
    }

    $DestVCThumbprint = $DestVCObj.Client.ConnectivityService.SslThumbPrint

    # Source VM to migrate
    $VMObj = Get-VM -Server $SourceVCObj -Name $VMName
    if (-not $VMObj) {
        Write-Error "Could not get source VM `"$VMName`""
        return
    }
    $vm_view = Get-View ($VMObj) -Property Config.Hardware.Device

    # Primary Dest Datastore to migrate VM to
    $datastore_view = (Get-Datastore -Server $DestVCObj -Name $Datastore[0])
    if (-not $datastore_view) {
        Write-Error "Could not get primay destination Datastore VM `"$($Datastore[0])`""
        return
    }

    # Dest Cluster/ResourcePool to migrate VM to
    if($Cluster) {
        $rp_view = Get-ResourcePool -Server $DestVCObj -Name $ResourcePool -Location $Cluster
    } else {
        $rp_view = Get-ResourcePool -Server $DestVCObj -Name $ResourcePool
    }
    $resource = $rp_view.ExtensionData.MoRef

    if ($resource -isnot [VMware.Vim.ManagedObjectReference]) {
        Write-Error "Could not get unique destination resource pool. ResurcePool: `"$ResourcePool`" Cluster: `"$Cluster`""
        return
    }

    # Dest ESXi host to migrate VM to
    $vmhost_view = (Get-VMHost -Server $DestVCObj -Name $VMHost)
    if (-not $vmhost_view) {
        Write-Error "Could not get destnation host `"$VMHost`""
        return
    }

    # Find all Etherenet Devices for given VM which
    # we will need to change its network at the destination
    $vmNetworkAdapters = @()
    $devices = $vm_view.Config.Hardware.Device
    foreach ($device in $devices) {
        if($device -is [VMware.Vim.VirtualEthernetCard]) {
            $vmNetworkAdapters += $device
        }
    }

    # Relocate Spec for Migration
    $spec = New-Object VMware.Vim.VirtualMachineRelocateSpec
    $spec.host = $vmhost_view.Id
    $spec.pool = $resource

    if ($Folder) {
        $FolderObj = $Folder
        if (-not $FolderObj.ExtensionData.MoRef) {
            $FolderObj = Get-Folder $Folder -Server $DestVCObj
        }
        if ($FolderObj.ExtensionData.MoRef -is [VMware.Vim.ManagedObjectReference]) {
            $spec.Folder = $FolderObj.ExtensionData.MoRef
        } else {
            Write-Error ("Could not get unique destination folder `"$Folder`". " +
                         "Assign the folder to a varable using Get-Folder and selecting one result or " +
                         "run Get-Item and use the vis:\ PSDrive to get the folder by its path."
                        )
            return
        }
    }

    # Relocate Spec Disk Locator
    $HDs = $VMObj | Get-HardDisk
    if($ComputeOnly){
        $i = 0
        $HDs | %{
            $disk = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator
            $disk.diskId = $_.Extensiondata.Key
            $SourceDS = $_.FileName.Split("]")[0].TrimStart("[")
            $DestDS = Get-Datastore -Server $DestVCObj -name $sourceDS
            $disk.Datastore = $DestDS.ID
            $spec.disk += $disk
            if ($i -eq 0) {
                $spec.datastore = $DestDS.ID
            }
        }
    } else {
        $spec.datastore = $datastore_view.Id
        $i = 0
        if ($Datastore.Count -gt 1) {
            $HDs | %{
                $disk = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator
                $disk.diskId = $_.Extensiondata.Key
                $DestDS = Get-Datastore -Server $DestVCObj -name $Datastore[$i]
                $disk.Datastore = $DestDS.ID
                $spec.disk += $disk
                $i++
            }
        }
    }

    # Service Locator for the destination vCenter Server
    # regardless if its within same SSO Domain or not
    $service = New-Object VMware.Vim.ServiceLocator
    $credential = New-Object VMware.Vim.ServiceLocatorNamePassword
    $credential.username = $DestCred.UserName
    $credential.password = $DestCred.GetNetworkCredential().Password
    $service.credential = $credential

    # For some xVC-vMotion, VC's InstanceUUID must be in all caps
    # Haven't figured out why, but this flag would allow user to toggle (default=false)
    $service.instanceUuid = ($DestVCObj.InstanceUuid).ToUpper()
    if($LowerCaseUUID) {
        $service.instanceUuid = $DestVCObj.InstanceUuid
    }

    $service.sslThumbprint = $DestVCThumbprint
    $service.url = "https://$DestVCObj"
    $spec.service = $service

    # Create VM spec depending if destination networking
    # is using Distributed Virtual Switch (VDS) or
    # is using Virtual Standard Switch (VSS)
    $count = 0
    if(-not $StandardSwitch) {
        foreach ($vmNetworkAdapter in $vmNetworkAdapters) {
            # New VM Network to assign vNIC
            $vmnetworkname = $VMNetwork[$count]

            # Extract Distributed Portgroup required info
            $dvpg = Get-VDPortgroup -Server $DestVCObj -Name $vmnetworkname
            $vds_uuid = (Get-View $dvpg.ExtensionData.Config.DistributedVirtualSwitch).Uuid
            $dvpg_key = $dvpg.ExtensionData.Config.key

            # Device Change spec for VSS portgroup
            $dev = New-Object VMware.Vim.VirtualDeviceConfigSpec
            $dev.Operation = "edit"
            $dev.Device = $vmNetworkAdapter
            $dev.device.Backing = New-Object VMware.Vim.VirtualEthernetCardDistributedVirtualPortBackingInfo
            $dev.device.backing.port = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
            $dev.device.backing.port.switchUuid = $vds_uuid
            $dev.device.backing.port.portgroupKey = $dvpg_key
            $spec.DeviceChange += $dev
            $count++
        }
    } else {
        foreach ($vmNetworkAdapter in $vmNetworkAdapters) {
            # New VM Network to assign vNIC
            $vmnetworkname = $VMNetwork[$count]

            # Device Change spec for VSS portgroup
            $dev = New-Object VMware.Vim.VirtualDeviceConfigSpec
            $dev.Operation = "edit"
            $dev.Device = $vmNetworkAdapter
            $dev.device.backing = New-Object VMware.Vim.VirtualEthernetCardNetworkBackingInfo
            $dev.device.backing.deviceName = $vmnetworkname
            $spec.DeviceChange += $dev
            $count++
        }
    }

    Write-Host "`nMigrating $VMName from $SourceVCObj to $DestVCObj ...`n"

    # Issue Cross VC-vMotion
    $task = $vm_view.RelocateVM_Task($spec,"defaultPriority")
    $task1 = Get-Task -Id ("Task-$($task.value)") -Server $SourceVCObj
    if ($Async) {
        return $task1
    } else {
        $task1 | Wait-Task
    }
}