# Deploying CoreOS via PowerShell

This script will automatically build out CoreOS clusters of a given size on enterprise VMware infrastructure. 

Taken from [this blog post](https://robertlabrie.wordpress.com/2015/09/27/coreos-on-vmware-using-vmware-guestinfo-api/) and expanded to include parameterized input, variable cluster size, and auto-generated/updated etcd discovery url.

# Parameters

* `NodeCount`: Defaults to 3, this is used to determine how many nodes are in the cluster (also used for generating IP addresses)
* `vCenterServer`: The target vCenter  Server (Defaults to my internal/isolated homelab... *change this for your implementation*)
* `ClusterDns`: DNS server for use by the nodes
* `ClusterGateway`: The node's IPv4 gateway
* `IPAddressStart`: The first node's IP address. This will be incremented for each subsequent node. **Note:** The current version does not check for valid IP addresses at run time. If you start at 10.3.1.250 and make a cluster of 11 nodes, this will probably break things.
* `Cidr`: Defaults to 24, this indicates the subnet mask in cidr notation
* `VMwareCred`: Credentials for connecting to `$vCenterServer`
* `CoreOSTemplate`: The name of the CoreOS template in vCenter

