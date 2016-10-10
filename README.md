# Deploying CoreOS via PowerShell

This script will automatically build out CoreOS clusters of a given size on enterprise VMware infrastructure. 

Taken from [this blog post](https://robertlabrie.wordpress.com/2015/09/27/coreos-on-vmware-using-vmware-guestinfo-api/) and expanded to include parameterized input, variable cluster size, and auto-generated/updated etcd discovery url.

# Cool things recently added
Now updated (but not tested) with the ability to specify public **and** private interfaces - more accurately emulating how things are setup in various public cloud service offerings.

# Parameters

* **`NodeCount`**: Defaults to 3, this is used to determine how many nodes are in the cluster (also used for generating IP addresses). Valid range from 1 to 20.
* **`vCenterServer`**: The target vCenter Server (Defaults to my internal/isolated homelab... change this for your implementation)
* **`ClusterDNS`**: DNS server for use by the nodes
* **`PubGateway`**: Each node's Public IPv4 gateway
* **`PrivGateway`**: Each node's Private IPv4 gateway
* **`PubIPStart`**: The first node's IP address. This will be incremented for each subsequent node. Note: The current version does not check for valid IP addresses at run time. If you start at 10.3.1.250 and make a cluster of 11 nodes, this will break things.
* **`PubIPStart`**: The first node's IP address. This will be incremented for each subsequent node. Note: The current version does not check for valid IP addresses at run time. If you start at 10.3.1.250 and make a cluster of 11 nodes, this will break things.
* **`Cidr`**: Defaults to 24, this indicates the subnet mask in cidr notation
* **`VMwareCred`**: PowerShell Credential object used to connect to the vCenterServer
* **`CoreOSTemplate`**: The name of the CoreOS template in vCenter

