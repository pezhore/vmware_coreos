<#
    .SYNOPSIS
    A script to build and maintain a CoreOS cluster: Builds any machines that don't exist, 
    Stops and updates machine .vmx file as necessary, Waits for machine to start before 
    taking down and updating next node

    .DESCRIPTION
    A script that will build and maintain a CoreOS cluster of a given size with specified
    network configuration from a given vCenter Template. Defaults to Brian's home lab
    environment. This is handled by injecting cloud-config.yml directly into the VM's vmx
    file prior to first boot.

    .EXAMPLE
    conjurevm.ps1 

    .PARAMETER NodeCount
    Defaults to 3, this is used to determine how many nodes are in the cluster (also used for generating IP addresses)
    Valid range from 1 to 20.

    .PARAMETER vCenterServer
    The target vCenter Server (Defaults to my internal/isolated homelab... change this for your implementation)

    .PARAMETER ClusterDNS
    DNS server for use by the nodes

    .PARAMETER PubGateway
    Each node's Public IPv4 gateway

    .PARAMETER PrivGateway
    Each node's Private IPv4 gateway

    .PARAMETER PubIPStart
    The first node's IP address. This will be incremented for each subsequent node. Note: The current version does 
    not check for valid IP addresses at run time. If you start at 10.3.1.250 and make a cluster of 11 nodes, 
    this will break things.

    .PARAMETER PubIPStart
    The first node's IP address. This will be incremented for each subsequent node. Note: The current version does 
    not check for valid IP addresses at run time. If you start at 10.3.1.250 and make a cluster of 11 nodes, 
    this will break things.

    .PARAMETER Cidr
    Defaults to 24, this indicates the subnet mask in cidr notation

    .PARAMETER VMwareCred
    PowerShell Credential object used to connect to the vCenterServer

    .PARAMETER CoreOSTemplate
    The name of the CoreOS template in vCenter

    .NOTES
    Author: Brian Marsh; Robert Labrie (robert.labrie@gmail.com)
#>

[CmdletBinding()]
param( 
      [Parameter(Mandatory = $false)]
      [ValidateRange(1,20)]
      [int] $NodeCount = 3,

      [Parameter(Mandatory = $false)]
      [System.Net.IPAddress] $vCenterServer = "10.0.0.153",
      
      [Parameter(Mandatory = $false)]
      [System.Net.IPAddress] $ClusterDNS = "8.8.8.8",

      [Parameter(Mandatory = $false)] 
      [System.Net.IPAddress] $PubGateway = "10.3.1.1",

      [Parameter(Mandatory = $false)] 
      [System.Net.IPAddress] $PrivGateway = "10.4.1.1",

      [Parameter(Mandatory = $false)]
      [System.Net.IPAddress] $PubIPStart = "10.3.1.20",

      [Parameter(Mandatory = $false)]
      [System.Net.IPAddress] $PrivIPStart = "10.4.1.20",

      [Parameter(Mandatory = $false)]
      [ValidateRange(0,32)]
      [int] $Cidr = 24,

      [Parameter(Mandatory = $false)]
      [PSCredential] $VMwareCred,

      [Parameter(Mandatory = $false)]
      [String] $CoreOSTemplate = "coreos_production_vmware_ova"
     )

BEGIN
{
    try
    {
        Import-Module VMware.VimAutomation.Core -ErrorAction Stop
    }
    catch
    {  
        Throw "Error loading VMware Module. Ensure it is available/installed before trying again."
    }


    # If no VMware Credential was provided, use default vCenter Credentials.
    if (! $VMwareCred)
    {
        # Yes. Plaintext passwords are bad. But this is a homelab that is rebuilt periodically.
        $DefaultPw = "vmware" | ConvertTo-SecureString -asPlainText -Force
        $VMwareCred = New-Object System.Management.Automation.PSCredential("administrator@vsphere.local",$DefaultPw)
    }
    
    # Get a etcd cluster discovery url with the given size
    $req = Invoke-WebRequest -Uri "https://discovery.etcd.io/new?size=$NodeCount"
    $req.Content

    # Get the current cloud-config content, then replace the existing discovery line with the new discovery url
    # This is kludgey and should probably be replaced by yaml manipulation
    try
    {
        $RawCloudConfig = get-content .\cloud-config.yml -raw -ErrorAction Stop | ForEach-Object {$_ -replace "discovery: .*", "discovery: $($req.Content)"}
    }
    catch
    {
        Write-Debug "Something Went Wrong... Debug?"
        Throw "Couldn't edit cloud-config: $($error[0].Exception)"
    }
}
PROCESS
{
    # Initialize Values
    $vmlist = @()
    $vminfo = @{}

    # Iterate through the Nodes, buildig out $vmlist & $vminfo
    for( [int]$Node = 1; $Node -le $NodeCount; $Node++)
    {
        #list of machines to make - hostname will be set to this unless overridden
        $vmlist += "coreos$node"

        # Determine our IP
        $PubIP  = ($PubIPStart.ToString().Split(".")[0,1,2] -join ".")+"."+$([int]($PubIPStart.ToString().Split(".")[3])+$Node)

        $PrivIP = ($PrivIPStart.ToString().Split(".")[0,1,2] -join ".")+"."+$([int]($PrivIPStart.ToString().Split(".")[3])+$Node)

        # Add hashmap of machine specific properties
        $vminfo["coreos$node"] = @{'interface.0.ip.0.address'="$PubIP/$Cidr";'interface.1.ip.0.address'="$PrivIP/$Cidr"}
    }

    # Hash properties that covers network config for all nodes
    $gProps = @{
        'dns.server.0'=$ClusterDNS;
        'interface.0.route.0.gateway'=$PubGateway;
        'interface.0.route.0.destination'='0.0.0.0/0';
        'interface.0.name' = 'ens192'; 
        'interface.0.role'='public';
        'interface.0.dhcp'='no';
        'interface.1.route.0.gateway'=$PrivGateway;
        'interface.1.route.0.destination'='0.0.0.0/0';
        'interface.1.name' = 'ens192'; 
        'interface.1.role'='private';
        'interface.1.dhcp'='no';
    }
write-debug "shittttt"
    #pack in the cloud config
    if (Test-Path .\cloud-config.yml)
    {
        # pull in the cloud config content
        #$RawCloudConfig = Get-Content "cloud-config.yml" -raw
        
        # Encode as UTf8 in bytes
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($RawCloudConfig)
        
        # Add to the properties hash the coreos config data & specify the encoding
        $gProps['coreos.config.data'] = [System.Convert]::ToBase64String($bytes)
        $gProps['coreos.config.data.encoding'] = 'base64'
    }
    else
    {
        Throw "No cloud-config.yml found. Please create and add to this folder"
    }

    # Connect to vCenter (Assuming no vCenters are already connected.
    if (!($global:DefaultVIServers.Count))
    { 
        Connect-VIServer $vCenterServer -Credential $VMwareCred
    }

    # Time to Build!
    #
    # Get the CoreOS template by name
    $template = Get-Template -Name $CoreOSTemplate

    # Get all VMHosts
    $vmhost = Get-VMHost

    # Initialize the tasks array (to contain/track the New-VM tasks)
    $tasks = @()

    # For each of our new CoreOS VMs
    foreach ($vmname in $vmlist)
    {
        # If there's already a VM that has this node's name, skip it.
        if (get-vm | Where-Object {$_.Name -eq $vmname }) 
        { 
            continue 
        }

        Write-Information -MessageData "Creating VM $vmname" -InformationAction Continue
        
        # Create the New VM
        $task = New-VM -Template $template -Name $vmname -host $vmhost -RunAsync

        # Add this task to the list
        $tasks += $task
    }

    #wait for pending builds to complete
    if ($tasks)
    {
        Write-Information -MessageData "Waiting for clones to complete" -InformationAction Continue
        foreach ($task in $tasks)
        {
            Wait-Task $task
        }
    }

    #setup and send the config
    foreach ($vmname in $vmlist)
    {
        # Get this VM's VM object & set a local path for the vm config file
        $vmxLocal = "$($ENV:TEMP)\$($vmname).vmx"
        $vm = Get-VM -Name $vmname
    
        #power off if running
        if ($vm.PowerState -eq "PoweredOn") 
        { 
            $vm | Stop-VM -Confirm:$false 
        }

        #fetch the VMX file
        $datastore = $vm | Get-Datastore
        $vmxRemote = "$($datastore.name):\$($vmname)\$($vmname).vmx"
        
        # If we already have a PS Drive for this datastore, remove it
        if (Get-PSDrive | Where-Object { $_.Name -eq $datastore.Name})
        { 
            Remove-PSDrive -Name $datastore.Name 
        }

        # Create a new PSDrive from the VM's datastore & Copy the config file to the local path
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
END
{
    Write-Debug "Anything else to do?"
}