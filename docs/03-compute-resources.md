# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. This lab provisions the compute resources required for running a secure and highly available Kubernetes cluster on a single physical machine running [Ubuntu Server](https://www.ubuntu.com/download/server) with KVM as the hypervisor. The lab uses [Ubuntu cloud images](http://cloud-images.ubuntu.com/) to make provisioning the VMs fast; these are pre-installed images and facilitates getting a working VM very quickly. This way, the lab can be run multiple times very quickly rather than spending the time required for installing the OS. The lab also uses [cloud-init](https://cloud-init.io/)

## Networking

This lab creates a switch on the host to which the cluster belongs. To isolate the network from the local network and to also use a similar address scheme as the [original](https://github.com/kelseyhightower/kubernetes-the-hard-way) tutorial, I have used [vyos](https://vyos.io/) in between the cluster network and the external switch. vyos will be connected to two bridges:
* br0 (connected to local network for internet connectivity)
* kube1 (KTHW cluster switch)

### Cluster Network

The configuration for /etc/network/interfaces is given below for both switches:

```
auto br0
iface br1 inet static
        address 192.168.2.250
        netmask 255.255.255.255
        network 192.168.2.250
        broadcast 192.168.2.255
        gateway 192.168.2.1
        dns-nameservers 10.240.0.31 10.240.0.32
        bridge_ports enp8s0
        bridge_stp off
        bridge_fd 0

auto kube1
iface kube1 inet static
        address 10.240.0.250
        netmask 255.255.255.0
        network 10.240.0.0
        broadcast 10.240.0.255
        gateway 10.240.0.1
        dns-nameservers 10.240.0.31 10.240.0.32
```

We will be using the same `10.240.0.0/24` IP address range which can host up to 254 compute instances.

> For a loadbalancer, we will be using [keepalived](http://www.keepalived.org/) to expose the Kubernetes API Servers.

List the firewall rules in the `kubernetes-the-hard-way` VPC network:

```
gcloud compute firewall-rules list --filter "network: kubernetes-the-hard-way"
```

> output

```
NAME                                         NETWORK                  DIRECTION  PRIORITY  ALLOW                 DENY
kubernetes-the-hard-way-allow-external       kubernetes-the-hard-way  INGRESS    1000      tcp:22,tcp:6443,icmp
kubernetes-the-hard-way-allow-internal       kubernetes-the-hard-way  INGRESS    1000      tcp,udp,icmp
```

### Kubernetes Public IP Address

Allocate a static IP address that will be attached to the external load balancer fronting the Kubernetes API Servers:

```
gcloud compute addresses create kubernetes-the-hard-way \
  --region $(gcloud config get-value compute/region)
```

Verify the `kubernetes-the-hard-way` static IP address was created in your default compute region:

```
gcloud compute addresses list --filter="name=('kubernetes-the-hard-way')"
```

> output

```
NAME                     REGION    ADDRESS        STATUS
kubernetes-the-hard-way  us-west1  XX.XXX.XXX.XX  RESERVED
```

## Compute Instances

The compute instances in this lab will be provisioned using [Ubuntu Server](https://www.ubuntu.com/server) 16.04, which has good support for the [cri-containerd container runtime](https://github.com/kubernetes-incubator/cri-containerd). Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.

### Kubernetes Controllers

Create three compute instances which will host the Kubernetes control plane:

```
for i in 0 1 2; do
  gcloud compute instances create controller-${i} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-1604-lts \
    --image-project ubuntu-os-cloud \
    --machine-type n1-standard-1 \
    --private-network-ip 10.240.0.1${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet kubernetes \
    --tags kubernetes-the-hard-way,controller
done
```

### Kubernetes Workers

Each worker instance requires a pod subnet allocation from the Kubernetes cluster CIDR range. The pod subnet allocation will be used to configure container networking in a later exercise. The `pod-cidr` instance metadata will be used to expose pod subnet allocations to compute instances at runtime.

> The Kubernetes cluster CIDR range is defined by the Controller Manager's `--cluster-cidr` flag. In this tutorial the cluster CIDR range will be set to `10.200.0.0/16`, which supports 254 subnets.

Create three compute instances which will host the Kubernetes worker nodes:

```
for i in 0 1 2; do
  gcloud compute instances create worker-${i} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-1604-lts \
    --image-project ubuntu-os-cloud \
    --machine-type n1-standard-1 \
    --metadata pod-cidr=10.200.${i}.0/24 \
    --private-network-ip 10.240.0.2${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet kubernetes \
    --tags kubernetes-the-hard-way,worker
done
```

### Verification

List the compute instances in your default compute zone:

```
gcloud compute instances list
```

> output

```
NAME          ZONE        MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP     STATUS
controller-0  us-west1-c  n1-standard-1               10.240.0.10  XX.XXX.XXX.XXX  RUNNING
controller-1  us-west1-c  n1-standard-1               10.240.0.11  XX.XXX.X.XX     RUNNING
controller-2  us-west1-c  n1-standard-1               10.240.0.12  XX.XXX.XXX.XX   RUNNING
worker-0      us-west1-c  n1-standard-1               10.240.0.20  XXX.XXX.XXX.XX  RUNNING
worker-1      us-west1-c  n1-standard-1               10.240.0.21  XX.XXX.XX.XXX   RUNNING
worker-2      us-west1-c  n1-standard-1               10.240.0.22  XXX.XXX.XX.XX   RUNNING
```

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
