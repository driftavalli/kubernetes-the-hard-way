# Kubernetes The Hard Way On KVM

Fork of Kelsey's Hightower [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) on a single machine KVM setup. Recreated as much of the support infrastructure as possible.

## Cluster Details

Kubernetes The Hard Way guides you through bootstrapping a highly available Kubernetes cluster with end-to-end encryption between components and RBAC authentication.

* [Kubernetes](https://github.com/kubernetes/kubernetes) 1.15.0
* [cri-o](https://github.com/cri-o/cri-o) 1.0.0-beta.0
* [CNI Container Networking](https://github.com/containernetworking/cni) 0.6.0
* [etcd](https://github.com/coreos/etcd) 3.2.11

## Labs

This tutorial attempts to create as much of the supporting infrastructure as possible. This means it uses more than the six (6) VM used by the original tutorial. It also assumes you have access to an Linux machine running KVM with sufficient resources. This usually means you have enough RAM as most CPU should be able to handle the load, (I have run this on a Thinkpad t450 with RAM upgraded to 32GB), reducing the memory assigned to the VMs should enable it to run on less resources but the Kubernetes cluster won't really support the deployment of applications. 

* [Prerequisites](docs/01-prerequisites.md)
* [Support Infrastructure](docs/02-support-infrastructure.md)
* [Installing the Client Tools](docs/04-client-tools.md)
* [Provisioning Compute Resources](docs/04-compute-resources.md)
* [Provisioning the CA and Generating TLS Certificates](docs/05-certificate-authority.md)
* [Generating Kubernetes Configuration Files for Authentication](docs/06-kubernetes-configuration-files.md)
* [Generating the Data Encryption Config and Key](docs/07-data-encryption-keys.md)
* [Bootstrapping the etcd Cluster](docs/08-bootstrapping-etcd.md)
* [Bootstrapping the Kubernetes Control Plane](docs/09-bootstrapping-kubernetes-controllers.md)
* [Bootstrapping the Kubernetes Worker Nodes](docs/10-bootstrapping-kubernetes-workers.md)
* [Configuring kubectl for Remote Access](docs/11-configuring-kubectl.md)
* [Provisioning Pod Network Routes](docs/12-pod-network-routes.md)
* [Deploying the DNS Cluster Add-on](docs/13-dns-addon.md)
* [Smoke Test](docs/14-smoke-test.md)
* [Cleaning Up](docs/15-cleanup.md)
