# Prerequisites

## Google Cloud Platform

This tutorial leverages open source applications (KVM, Keepalived, BIND) to replicate KTHW on a single box, using it as a learning tool.

Estimated cost: Free (If you have an appropriate machine)

## Required tools
* bridge-utils
* genisoimage
* qemu-uitls
* virt-install

### Install tools
  #### [bridge-utils](https://wiki.linuxfoundation.org/networking/bridge)
  Bridge administration utilities that can be used to create and manage bridges (switches) 
    ```
    sudo apt install bridge-utils
    ```
  #### [genisoimage](https://wiki.debian.org/genisoimage)
  CLI for creating ISO images
    ```
    sudo apt install genisoimage
    ```
  #### [qemu-utils](https://packages.debian.org/sid/qemu-utils)
  QEMU administration utility that includes a disk image creator.
    ```
    sudo apt install qemu-utils
    ```
  #### [virt-install](https://packages.debian.org/sid/virtinst)
  CLI that can be used to create VMs using libvirt.
    ```
    sudo apt install virtinst
    ```

Next: [Installing the Client Tools](02-client-tools.md)
