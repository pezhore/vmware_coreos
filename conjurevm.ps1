<#
A script to build and maintain a CoreOS cluster
- Builds any machines that don't exist
- Stops and updates machine .vmx file as necessary
- Waits for machine to start before taking down and updating next node

Author: robert.labrie@gmail.com
Additional Magic: Brian Marsh
#>
[CmdletBinding()]
param( $NodeCount=3,
       $vCenterServer = "10.0.0.153",
       $ClusterDNS = "10.3.1.1",
       $ClusterGateway = "10.3.1.1",
       $IPaddressStart = "10.3.1.20",
       $Cidr = 24,
       $VMwareCred,
       $CoreOSTemplate = "coreos_production_vmware_ova"
     )
BEGIN
{
    if (! $VMwareCred)
    {
        $DefaultPw = "vmware" |ConvertTo-SecureString -asPlainText -Force
        $VMwareCred = New-Object System.Management.Automation.PSCredential("administrator@vsphere.local",$DefaultPw)
    }
    

    # Get a new three node cluster discovery url
    $req = Invoke-WebRequest -Uri 'https://discovery.etcd.io/new?size=3'
    $req.Content

    # Get the current cloud-config content, then replace the existing discovery line with the new discovery url
    get-content .\cloud-config.yml | ForEach-Object {$_ -replace "discovery: .*", "discovery: $($req.Content)"} | Set-Content .\cloud-config.yml
}
PROCESS
{
    # Initialize Values
    $vmlist = @()
    $vminfo = @{}

    for( [int]$Node = 1; $Node -le $NodeCount; $Node++)
    {
        #list of machines to make - hostname will be set to this unless overridden
        $vmlist += "coreos$node"

        # Determine our IP
        $thisIP = ($IPaddressStart.Split(".")[0,1,2] -join ".")+"."+$([int]($IPaddressStart.Split(".")[3])+$Node)
        # Add hashmap of machine specific properties
        $vminfo["coreos$node"] = @{'interface.0.ip.0.address'="$thisIP/$Cidr"}
    }

    #hashmap of properties common for all machines
    $gProps = @{
        'dns.server.0'=$ClusterDNS;
        'interface.0.route.0.gateway'=$ClusterGateway;
        'interface.0.route.0.destination'='0.0.0.0/0';
        'interface.0.name' = 'ens192'; 
        'interface.0.role'='private';
        'interface.0.dhcp'='no';}

    #pack in the cloud config
    if (Test-Path .\cloud-config.yml)
    {
        $cc = Get-Content "cloud-config.yml" -raw
        $b = [System.Text.Encoding]::UTF8.GetBytes($cc)
        $gProps['coreos.config.data'] = [System.Convert]::ToBase64String($b)
        $gProps['coreos.config.data.encoding'] = 'base64'
    }

    #load VMWare snapin and connect
    Add-PSSnapin VMware.VimAutomation.Core
    if (!($global:DefaultVIServers.Count)) { Connect-VIServer $vCenterServer -Credential $VMwareCred}

    #build the VMs as necessary
    $template = Get-Template -Name $CoreOSTemplate
    $vmhost = Get-VMHost
    $tasks = @()
    foreach ($vmname in $vmlist)
    {
        if (get-vm | Where-Object {$_.Name -eq $vmname }) { continue }
        Write-Host "creating $vmname"
        $task = New-VM -Template $template -Name $vmname -host $vmhost -RunAsync
        $tasks += $task
    }

    #wait for pending builds to complete
    if ($tasks)
    {
        Write-Host "Waiting for clones to complete"
        foreach ($task in $tasks)
        {
            Wait-Task $task
        }
    }

    #setup and send the config
    foreach ($vmname in $vmlist)
    {
        $vmxLocal = "$($ENV:TEMP)\$($vmname).vmx"
        $vm = Get-VM -Name $vmname
    
        #power off if running
        if ($vm.PowerState -eq "PoweredOn") { $vm | Stop-VM -Confirm:$false }

        #fetch the VMX file
        $datastore = $vm | Get-Datastore
        $vmxRemote = "$($datastore.name):\$($vmname)\$($vmname).vmx"
        if (Get-PSDrive | Where-Object { $_.Name -eq $datastore.Name}) { Remove-PSDrive -Name $datastore.Name }
        $null = New-PSDrive -Location $datastore -Name $datastore.Name -PSProvider VimDatastore -Root "\"
        Copy-DatastoreItem -Item $vmxRemote -Destination $vmxLocal
    
        #get the file and strip out any existing guestinfo
        $vmx = ((Get-Content $vmxLocal | Select-String -Pattern guestinfo -NotMatch) -join "`n").Trim()
        $vmx = "$($vmx)`n"

        #build the property bag
        $props = $gProps
        $props['hostname'] = $vmname
        $vminfo[$vmname].Keys | ForEach-Object {
            $props[$_] = $vminfo[$vmname][$_]
        }

        #add to the VMX
        $props.Keys | ForEach-Object {
            $vmx = "$($vmx)guestinfo.$($_) = ""$($props[$_])""`n" 
        }

        #write out the VMX
        $vmx | Out-File $vmxLocal -Encoding ascii

        #replace the VMX in the datastore
        Copy-DatastoreItem -Item $vmxLocal -Destination $vmxRemote

        #start the VM
        $vm | Start-VM
        $status = "toolsNotRunning"
        while ($status -eq "toolsNotRunning")
        {
            Start-Sleep -Seconds 1
            $status = (Get-VM -name $vmname | Get-View).Guest.ToolsStatus
        }
    
    }
}