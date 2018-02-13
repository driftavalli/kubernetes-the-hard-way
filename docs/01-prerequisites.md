# Prerequisites

## Google Cloud Platform

This is based on Kelsey Hightowers Kubernetes the hard war but instead leverages KVM, Keepalived, BIND (all open source and free applications) to replicate KTHW on a single box, using it as a learning tool.

Estimated cost: Free (If you have an appropriate machine)

## Required tools
The intent is to replicate KTHW as closely as possible; to this end, keepalived is used to provide loadbalancing across the controller hosts and BIND is used to provide name resolution for the IP address. In total, we will setup 4 extra VMs for the loadbalancer and DNS server.
These are the tools used to create the VM's on the KVM host. I have added the links I that seemed most relevant but may not necessarily be the only/best link. Install these on the KVM host.
* bridge-utils
* genisoimage
* qemu-uitls
* virt-install
* virsh

### Install tools
  #### [bridge-utils](https://wiki.linuxfoundation.org/networking/bridge)
  Bridge administration utilities that can be used to create and manage bridges (switches):
  
    
    sudo apt install bridge-utils
    
    
  #### [genisoimage](https://wiki.debian.org/genisoimage)
  CLI for creating ISO images:
  
    
    sudo apt install genisoimage
    
    
  #### [qemu-utils](https://packages.debian.org/sid/qemu-utils)
  QEMU administration utility that includes a disk image creator:
  
    
    sudo apt install qemu-utils
    
    
  #### [virt-install](https://packages.debian.org/sid/virtinst)
  CLI that can be used to create VMs using libvirt:
  
    
    sudo apt install virtinst
  
  #### [virsh](https://linux.die.net/man/1/virsh)
  virsh is the main interface for managing virsh guest domains
  
  
    sudo apt install libvirt-clients
  
    

Next: [Installing the Client Tools](02-client-tools.md)
