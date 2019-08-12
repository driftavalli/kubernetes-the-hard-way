## Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. This lab provisions the compute resources required for running a secure and highly available Kubernetes cluster on a single physical machine running [Ubuntu Server](https://www.ubuntu.com/download/server) with KVM as the hypervisor. The lab uses [Ubuntu cloud images](http://cloud-images.ubuntu.com/) to make provisioning the VMs fast; these are pre-installed images and facilitates getting a working VM very quickly. This way, the lab can be run multiple times very quickly rather than spending the time required for installing the OS. The lab also uses [cloud-init](https://cloud-init.io/)

## Networking

This lab creates a switch on the host to which the cluster belongs. The plan is to explore federation of different Kubernetes cluster and to make configuration and separtion of the VM traffic more managable, an OVS switch. This enables us to specify the VLAN tag as the VM is being provisioned. Routing is currently done on an external Layer 3 switch (in this case, a HP Procurve 3500) but we'll probably install an [FRR](https://frrouting.org/) VM and make the whole lab self contained.

### Cluster Network

The configuration for /etc/netplan/01-netcfg.yaml is given below:

```
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:
      dhcp4: no
      optional: true
    enp4s0:
      dhcp4: no
      optional: true      
  bridges:
    br0:
      dhcp4: no
      optional: true
      addresses: [ 10.240.10.254/24 ]
      gateway4: 10.240.10.1
      nameservers:
        search: [ homelab.test ]
        addresses: [ 1.1.1.1, 9.9.9.9 ]
      interfaces:
        - enp3s0
```

`sudo ovs-vsctl show`

```
ef9e373e-64d7-48df-ae66-e3433a89452d
    Bridge "enp7"
        Port "enp4s0"
            Interface "enp4s0"
                type: internal
    ovs_version: "2.11.1"
```

We will be using the `10.240.70.0/24` IP address range which can host up to 254 compute instances.

> For a loadbalancer, we will be using [keepalived](http://www.keepalived.org/) to expose the Kubernetes API Servers.


#### Kubernetes Public IP Address

For the Kubernetes Public IP, we'll be using the IP configured on the Keepalived loadbalancer. If we have our infrastructure setup from the preceding section, then we should be able to retrieve the IP by running the command below:

```
dig +short apiserver.homelab.test
10.240.70.100
```

## Compute Instances

The compute instances in this lab will be provisioned using [Ubuntu Cloud images](https://cloud-images.ubuntu.com/). Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.

Before creating the compute instances we'll create a base image to use that should make subsequent attempts more efficient.

First, we'll download the image:

`curl -O --progress-bar --ssl-reqd --trace-time https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img`

Make copies of the image for the controller and worker nodes and resize the copied images:

~~## Check Disk sizes~~

~~##  qemu-img info controller.img~~

~~##  qemu-img info worker.img~~
```
cp bionic-server-cloudimg-amd64.img controller.img
cp bionic-server-cloudimg-amd64.img worker.img
qemu-img resize controller.img +40G
qemu-img resize worker.img +40G
```

We should still have the cloud-init files from the previous module.

<pre><code>
cat &lt;&lt;EOF | tee ~/tmp/backup/user-data.bak
#cloud-config
users:
  - name: <b>USERNAME</b>
    gecos: <b>USERNAME</b>
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: sudo
    lock_passwd: false
    passwd: <b>PASSWORD_HASH</b>
    ssh-authorized-keys:
      - <b>SSH_KEYS</b>
manage_etc_hosts: localhost
package_upgrade: true
power_state:
  delay: "+1"
  mode: reboot
  message: Bye Bye
  timeout: 1 
  condition: True
timezone: Canada/Eastern
EOF
</code></pre>

meta-data
<pre><code>
cat &lt;&lt;EOF | tee ~/tmp/backup/meta-data.backup
instance-id: iid-instance00
local-hostname: keepalived
EOF
</code></pre>

network-config
<pre><code>
cat &lt;&lt;EOF | tee ~/tmp/backup/network-config.bak
version: 2
ethernets:
  ens3:
    dhcp4: false
    dhcp6: false
    addresses:
      - 10.240.70.70/24
    optional: true
    gateway4: 10.240.80.1
    nameservers:
      search:
        - homelab.test
      addresses:
        - 10.240.70.81
EOF        
</code></pre>

We'll use these to create the base images:
#### Worker Image Configuration
```
for i in user-data meta-data network-config; do
  if [ -f ${i} ];
    then rm ${i};
  fi
  cp bak/${i}.bak ${i};
done
printf "apt_sources:\n  - source: \"ppa:projectatomic/ppa\"\n" >> user-data
printf "packages:\n  - socat\n  - conntrack\n  - ipset\n  - apt-transport-https\n  - ca-certificates\n  - curl\n  - software-properties-common\n  - cri-o-1.13\n  - containernetworking-plugins\n  - buildah\n  - conmon\n  - cri-o-runc\n  - podman\n  - skopeo\n" >> user-data
printf "runcmd:\n  - rm /etc/cni/net.d/100* /etc/cni/net.d/87* /etc/cni/net.d/200*\n  - apt autoremove -y\n  - apt update\n" >> user-data
printf "write_files:\n  - encoding: b64\n    content: ewogICAgImNuaVZlcnNpb24iOiAiMC4zLjEiLAogICAgInR5cGUiOiAibG9vcGJhY2siCn0K\n    path: /etc/cni/net.d/99-loopback.conf\n  - encoding: b64\n    content: bmV0LmJyaWRnZS5icmlkZ2UtbmYtY2FsbC1pcHRhYmxlcyAgPSAxCm5ldC5pcHY0LmlwX2ZvcndhcmQgICAgICAgICAgICAgICAgICAgICA9IDEKbmV0LmJyaWRnZS5icmlkZ2UtbmYtY2FsbC1pcDZ0YWJsZXMgPSAx\n    path: /etc/sysctl.d/99-kubernetes-cri.conf\n  - encoding: b64\n    content: b3ZlcmxheQ==\n    path: /etc/modules-load.d/overlay.conf\n  - encoding: b64\n    content: YnJfbmV0ZmlsdGVy\n    path: /etc/modules-load.d/br_netfilter.conf\n" >> user-data
for i in 1; do
  sed -i "s?controller?worker?" user-data
  sed -i -e "s?instance00?worker?" -e "s?initial?worker?" meta-data
  sed -i -e "s?.60?.5${i}?" -e "s?1.1.1.1?10.240.70.81?"  -e "s?9.9.9.9?10.240.70.82?" network-config
  genisoimage  -output /vm/tmp/iso/worker.iso -volid cidata -joliet -rock user-data meta-data network-config
done
```

#### Controller Image Configuration
```
for i in user-data meta-data network-config; do
  if [ -f ${i} ]; 
    then rm ${i};
  fi
  cp bak/${i}.bak ${i};
done;
printf "apt_sources:\n  - source: \"ppa:projectatomic/ppa\"\n" >> user-data
printf "packages:\n  - nginx\n  - socat\n  - conntrack\n  - ipset\n  - apt-transport-https\n  - ca-certificates\n  - curl\n  - software-properties-common\n  - cri-o-1.13\n  - containernetworking-plugins\n  - buildah\n  - conmon\n  - cri-o-runc\n  - podman\n  - skopeo\n" >> user-data
printf "runcmd:\n  - rm /etc/cni/net.d/100* /etc/cni/net.d/87* /etc/cni/net.d/200*\n  - apt autoremove -y\n  - apt update\n" >> user-data
printf "write_files:\n  - encoding: b64\n    content: ewogICAgImNuaVZlcnNpb24iOiAiMC4zLjEiLAogICAgInR5cGUiOiAibG9vcGJhY2siCn0K\n    path: /etc/cni/net.d/99-loopback.conf\n  - encoding: b64\n    content: bmV0LmJyaWRnZS5icmlkZ2UtbmYtY2FsbC1pcHRhYmxlcyAgPSAxCm5ldC5pcHY0LmlwX2ZvcndhcmQgICAgICAgICAgICAgICAgICAgICA9IDEKbmV0LmJyaWRnZS5icmlkZ2UtbmYtY2FsbC1pcDZ0YWJsZXMgPSAx\n    path: /etc/sysctl.d/99-kubernetes-cri.conf\n  - encoding: b64\n    content: b3ZlcmxheQ==\n    path: /etc/modules-load.d/overlay.conf\n  - encoding: b64\n    content: YnJfbmV0ZmlsdGVy\n    path: /etc/modules-load.d/br_netfilter.conf\n" >> user-data
printf "  lo:\n    dhcp4: false\n    dhcp6: false\n    optional: true\n    addresses:\n      - 10.240.70.100/32\n " >> network-config
for i in 1; do
  sed -i "s?controller?controller?" user-data
  sed -i -e "s?instance00?controller?" -e "s?initial?controller?" meta-data
  sed -i -e "s?.60?.6${i}?" -e "s?1.1.1.1?10.240.70.81?"  -e "s?9.9.9.9?10.240.70.82?" network-config
  genisoimage  -output /vm/tmp/iso/controller.iso -volid cidata -joliet -rock user-data meta-data network-config
done
```

### Install Base Images
## Compute Instances

### Controllers
```
virt-install --name controller \
  --ram=8192 --vcpus=4 --cpu host --hvm \
  --disk path=/vm/tmp/backingImage/controller.img \
  --import --disk path=/vm/tmp/iso/controller.iso,device=cdrom \
  --network bridge=enp7,model=virtio,virtualport_type=openvswitch \
  --os-type=linux --os-variant=ubuntu18.04 \
  --noautoconsole &
```

### Workers
```
virt-install --name worker \
  --ram=8192 --vcpus=2 --cpu host --hvm \
  --disk path=/vm/tmp/backingImage/worker.img \
  --import --disk path=/vm/tmp/iso/worker.iso,device=cdrom \
  --network bridge=enp7,model=virtio,virtualport_type=openvswitch \
  --os-type=linux --os-variant=ubuntu18.04 \
  --noautoconsole &
```

If we connect to the VM from the console (`virsh console controller`), we should be able to see the download and installation process; once it is complete, we run `cloud-init clean` to reset cloud-init and shutdown down the VMs. Then we undefine them `virsh undefine controller` &&  `virsh undefine worker`. We should now have two images named controller.img and worker.img that will be the base for our Kubernetes cluster nodes.

We will go ahead and create the images for the instances

##### controller instance images
```
for i in user-data meta-data network-config; do
  if [ -f cloud-init/${i} ]; 
    then rm cloud-init/${i};
  fi
  cp bak/${i}.bak cloud-init/${i};
done;
printf "  lo:\n    dhcp4: false\n    dhcp6: false\n    optional: true\n    addresses:\n      - 10.240.70.100/32\n " >> cloud-init/network-config
for i in 0 1 2; do
  sed -i "s?controller?controller-${i}?" cloud-init/user-data
  sed -i -e "s?instance00?controller-${i}?" -e "s?initial?controller-${i}?" cloud-init/meta-data
  sed -i -e "s?.60?.1${i}?" -e "s?1.1.1.1?10.240.70.81?"  -e "s?9.9.9.9?10.240.70.82?" cloud-init/network-config
  genisoimage  -output /vm/tmp/iso/controller-${i}.iso -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data cloud-init/network-config
  qemu-img create -f qcow2 -o backing_file=/vm/tmp/backingImage/controller.img /vm/tmp/images/controller-${i}.img
  rm cloud-init/user-data cloud-init/meta-data cloud-init/network-config
  for j in user-data meta-data network-config; do
    cp bak/${j}.controller cloud-init/${j};
  done;
  printf "  lo:\n    dhcp4: false\n    dhcp6: false\n    optional: true\n    addresses:\n      - 10.240.70.100/32\n " >> cloud-init/network-config
done
```

##### Worker instance images
```
for i in user-data meta-data network-config; do
  if [ -f cloud-init/${i} ];
    then rm cloud-init/${i};
  fi
  cp bak/${i}.worker cloud-init/${i};
done

for i in 0 1 2; do
  sed -i "s?controller?worker-${i}?" cloud-init/user-data
  sed -i -e "s?instance00?worker-${i}?" -e "s?initial?worker-${i}?" cloud-init/meta-data
  sed -i -e "s?.60?.2${i}?" -e "s?1.1.1.1?10.240.70.81?"  -e "s?9.9.9.9?10.240.70.82?" cloud-init/network-config
  genisoimage  -output /vm/tmp/iso/worker-${i}.iso -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data cloud-init/network-config
  qemu-img create -f qcow2 -o backing_file=/vm/tmp/backingImage/worker.img /vm/tmp/images/worker-${i}.img
  rm cloud-init/user-data cloud-init/meta-data cloud-init/network-config
  for j in user-data meta-data network-config; do
    cp bak/${j}.worker cloud-init/${j};
  done;
done
```

### Kubernetes Controllers
Create three compute instances which will host the Kubernetes control plane:

```
for i in 0 1 2; do
  virt-install --name controller-${i} \
    --ram=8192 --vcpus=4 --cpu host --hvm \
    --disk path=/vm/tmp/images/controller-${i}.img \
    --import --disk path=/vm/tmp/iso/controller-${i}.iso,device=cdrom \
    --network bridge=enp7,model=virtio,virtualport_type=openvswitch \
    --os-type=linux --os-variant=ubuntu18.04 \
    --noautoconsole &
done
```

### Kubernetes Workers
Create three compute instances which will host the Kubernetes worker nodes:

```
for i in 0 1 2; do
  virt-install --name worker-${i} \
    --ram=8192 --vcpus=2 --cpu host --hvm \
    --disk path=/vm/tmp/images/worker-${i}.img \
    --import --disk path=/vm/tmp/iso/worker-${i}.iso,device=cdrom \
    --network bridge=enp7,model=virtio,virtualport_type=openvswitch \
    --os-type=linux --os-variant=ubuntu18.04 \
    --noautoconsole &
done
```

### Verification

List the compute instances in your default compute zone:

```
virsh list --all
```

> output

```
Id    Name                           State
----------------------------------------------------
 1     powerdns-1                     running
 2     powerdns-2                     running
 3     powerdns-3                     running
 4     keepalived-1                   running
 5     keepalived-2                   running
 324   worker-0                       running
 325   controller-1                   running
 326   worker-2                       running
 327   controller-2                   running
 328   controller-0                   running
 329   worker-1                       running

```

Next: [Provisioning a CA and Generating TLS Certificates](05-certificate-authority.md)
