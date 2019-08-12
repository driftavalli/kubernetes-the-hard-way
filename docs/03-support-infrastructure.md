# Infrastructure setup
## Install KVM
We'll be using KVM as the hypervisor. Installation of KVM won't be covered here as there are lots of good articles that describe how to do that. Check [KVM Installation](https://help.ubuntu.com/community/KVM/Installation) for how to get started.

## Create bridge
We will configure our NIC to act as a bridge to which we will connect the VMs to. This allows the possibility of running multiple clusters on the same machine. The config below uses [netplan](https://netplan.io) to setup the bridge on the system, however the network configuration to enable this is out of scope and won't be covered here. 

```
cat <<EOF | sudo tee /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:
      dhcp4: no
      optional: true
  bridges:
    br0:
      dhcp4: no
      optional: true
      addresses: [ 10.240.80.254/24 ]
      gateway4: 10.240.80.1
      nameservers:
        search: [ homelab.test ]
        addresses: [ 1.1.1.1, 9.9.9.9 ]
        interfaces:
            - enp3s0
EOF
```
Then to activate the configuration, run

`sudo netplan generate`

`sudo netplan apply`

If everything is setup correctly, you should have a bridge assigned with a static IP.

## Create Base Image for installation of [Keepalived](http://www.keepalived.org)
We will be using [Ubuntu cloud images](https://cloud-images.ubuntu.com) to build a base image for Keepalived. A lot of the heavy lifting for setting up the server will also be done using [cloud-init](https://cloud-init.io/) which the cloud images support. While not particularly suited for configuration management, we will use it here for now (more suitable options for configuration management for servers include [ansible](https://www.ansible.com/), [chef](https://www.chef.io/), [puppet](https://puppet.com/). Eventually, we will probably replace the setup with [terraform](https://www.terraform.io/) which should make setting up the servers a breeze. Download the image for [Ubuntu 18.04 LTS (Bionic Beaver)](https://cloud-images.ubuntu.com/bionic/current/). I prefer having a folder structure I can easily delete when I am all done. So I will be creating a playground folder and all the files downloaded and created will be stored in that folder.

`mkdir -p ~/tmp/backup ~/tmp/downloads ~/tmp/backingImages ~/tmp/iso ~/tmp/images ~/tmp/sshkeys/`

`cd ~/tmp/downloads`

`wget https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img`

`cp bionic-server-cloudimg-amd64.img /home/tmp/backingImages/keepalived.img`

### Install Base Image VM in KVM
#### First Create `user-data`, `meta-data` and `network-config` files.
Ubuntu does not have the most recent version of Keepalived so we will download the tar and install the latest version from the [keepalived](https://www.keepalived.org/software/keepalived-2.0.17.tar.gz) website. Create password hash using `mkpasswd --method=SHA-512 --rounds=4096`, requires installing `whois`: `sudo apt install whois`. Replace italicized bold variables with your own.

`cd ~/tmp/sshkeys/`

`ssh-keygen -t rsa -b 4096 -C "kthw@homelab.test"`

At the prompt, enter path to sshkeys directory: /home/$USER/tmp/sshkeys/id_kthw. You should then find two files, `id_kthw` and `id_kthw.pub`. We will use the .pub later on.

`mkpasswd --method=SHA-512 --rounds=4096 > passwd.hash`

`cd ~/home/backup/` _Remember to replace USERNAME, PASSWORD_HASh_

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

### Create ISO
```
cd ~/tmp/
```

```
for i in user-data network-config meta-data; do
  cp /home/$USER/tmp/backup/$i.bak $i
done
```

We will add some configuration to download and install keepalived to user-data (Ideally, this should be handled using configuration management tools like [Ansible](https://www.ansible.com/), [Chef](https://www.chef.io/), [Puppet](https://puppet.com/))
```
printf "runcmd:\n  - apt autoremove\n  \
  - curl --progress https://keepalived.org/software/keepalived-2.0.17.tar.gz | tar xz -C\n  \
  - cd keepalived-2.0.17\n  - ./configure --prefix=/usr/local/keepalived-2.0.17\n  \
  - make\n  - sudo make install\n  - ln -s /usr/local/keepalived-2.0.17 /usr/local/keepalived\n  \
  - echo \"net.ipv4.ip_forward=1\" >> /etc/sysctl.conf\n" >> user-data

```

```
genisoimage  -output /home/$USER/tmp/iso/keepalived.iso \
  -volid cidata -joliet -rock user-data meta-data network-config
```

### Create Keepalived VM Compute Instance
```
cd ~/tmp/
```

<pre><code>
virt-install --name keepalived \
  --ram=512 --vcpus=1 --cpu host --hvm \
  --disk path=/home/$USER/tmp/backingImages/keepalived.img \
  --import --disk path=/home/$USER/tmp/iso/keepalived.iso,device=cdrom \
  --network bridge=br0,model=virtio,virtualport_type=openvswitch \
  --noautoconsole --os-variant=ubuntu18.04
</code></pre>

#### Log into the VM and create systemd service file
`virsh console keepalived`

```
cat <<EOF | sudo tee /etc/systemd/system/keepalived.service
[Unit]
Description=Keepalive Daemon (LVS and VRRP)
After=syslog.target network-online.target
Wants=network-online.target
# Only start if there is a configuration file
ConditionFileNotEmpty=/etc/keepalived/keepalived.conf

[Service]
Type=forking
KillMode=process
# Read configuration variable file if it is present
EnvironmentFile=-/etc/default/keepalived
ExecStart=/usr/sbin/keepalived $DAEMON_ARGS
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
```

#### Reset Cloud-Init
`sudo cloud-init clean`

`sudo shutdown -h now`

#### Remove VM from libvirt
`virsh undefine keepalived`

`rm keepalived.iso`


We now have a base image for keepalived we can use over and over. We will use the script below to auto create two vms: keepalived-1 and keepalived-2.

<pre><code>
cat &lt;&lt;EOF | tee keepalived.sh
#!/bin/bash
## Remove any old configuration files for cloud-init
for i in user-data meta-data network-config; do
  if [ -f ${i} ]; 
    then rm ${i};
  fi
  cp backup/${i}.backup ${i};
done;
for i in 1 2; do
  sed -i -e "s?keepalived?keepalived-${i}?" -e "s?iid-instance00?iid-keepalived${i}?" meta-data
  sed -i -e "s?.70?.7${i}?" network-config
  genisoimage  -output /home/$USER/tmp/iso/keepalived-${i}.iso -volid cidata -joliet -rock user-data meta-data network-config
  qemu-img create -f qcow2 -o backing_file=/home/$USER/tmp/backingImage/keepalived.img /home/$USER/tmp/images/keepalived-${i}.img 40G
  rm user-data meta-data network-config
  for j in user-data meta-data network-config; do
    cp bak/${j}.backup ${j};
  done;
done

## Create Compute Instances
for i in 1 2; do
  virt-install --name keepalived-${i} \
    --ram=512 --vcpus=1 --cpu host --hvm \
    --disk path=/home/$USER/tmp/images/keepalived-${i}.img \
    --import --disk path=/home/$USER/tmp/iso/keepalived-${i}.iso,device=cdrom \
    --network bridge=br0,model=virtio,virtualport_type=openvswitch \
    --noautoconsole --os-variant=ubuntu18.04
done
</code></pre>

### Configure Keepalived
After allowing a few minutes for the VMs to start, we will login and configure each one. We should be able to login using ssh if we added our public keys to the `user-data` configuration earlier. The Keepalived configuration has been setup with the foreknowledge of the IPs we'll be assigning to our apiservers and the loadbalanced nodes. Keepalived does not currently have an api to dynamically update it's configuration. [Facebook's Katran](https://github.com/facebookincubator/katran) looks to be an interesting project in addition to [github.com GLB](https://github.com/github/glb-director); The choice of loadbalancer will probably be revisited. We have also configured checks for the nginx webserver and the https endpoint. These will be clearer later on.
#### LB-1
<pre><code>
cat &lt;&lt;EOF | sudo tee /etc/keepalived/keepalived.conf
! Configuration File for keepalived

global_defs {
  notification_email {
    keepalived@homelab.test
  }
  notification_email_from keepalived-1@homelab.test
! UNIQUE:
  router_id KEEPALIVED_1
}

! ***********************************************************************
! *************************   WEB SERVICES VIP  *************************
! ***********************************************************************
vrrp_instance VirtIP_10 {
  state MASTER
  interface ens3
  virtual_router_id 10

! UNIQUE:
  priority 150
  advert_int 3
  smtp_alert
  authentication {
      auth_type PASS
      auth_pass homelab
  }

  use_mac

  virtual_ipaddress {
      10.240.80.100
  }
}

! ************************   WEB SERVERS  **************************

virtual_server 10.240.80.100 6443 {
  delay_loop 10
  lb_algo wrr
  lb_kind DR
  persistence_timeout 5
  protocol TCP

  real_server 10.240.80.10 6443 {
    weight 1
    MISC_CHECK {
        misc_path /etc/keepalived/healthz.sh
    }
  }

  real_server 10.240.80.11 6443 {
    weight 1
    MISC_CHECK {
        misc_path /etc/keepalived/healthz.sh
    }
  }

  real_server 10.240.80.12 6443 {
    weight 1
    MISC_CHECK {
          misc_path /etc/keepalived/healthz.sh
    }
  }

virtual_server 10.240.80.100 80 {
  delay_loop 10
  lb_algo wrr
  lb_kind DR
  persistence_timeout 5
  protocol TCP

  real_server 10.240.80.10 80 {
      weight 1
      TCP_CHECK {
          connect_timeout 3
      }
  }

  real_server 10.240.80.11 80 {
      weight 1
      TCP_CHECK {
          connect_timeout 3
      }
  }

  real_server 10.240.80.12 80 {
      weight 1
      TCP_CHECK {
          connect_timeout 3
      }
    }
}

</code></pre>

#### LB-2
<pre><code>
cat &lt;&lt;EOF | sudo tee /etc/keepalived/keepalived.conf
! Configuration File for keepalived

global_defs {
  notification_email {
    keepalived@homelab.test
  }
  notification_email_from keepalived-2@homelab.test
! UNIQUE:
  router_id KEEPALIVED_2
}

! ***********************************************************************
! *************************   WEB SERVICES VIP  *************************
! ***********************************************************************

vrrp_instance VirtIP_10 {
  state BACKUP
  interface ens3
  virtual_router_id 10
  
! UNIQUE:
  priority 50
  advert_int 3
  smtp_alert
  authentication {
    auth_type PASS
    auth_pass homelab 
  }

  use_vmac

  virtual_ipaddress {
    10.240.80.100
  }
}

! ************************   WEB SERVERS  **************************

virtual_server 10.240.80.100 6443 {
  delay_loop 10
  lb_algo wrr
  lb_kind DR
  persistence_timeout 5
  protocol TCP

  real_server 10.240.80.10 6443 {
    weight 1
    MISC_CHECK {
      misc_path /etc/keepalived/healthz.sh
    }
  }

  real_server 10.240.80.11 6443 {
    weight 1
    MISC_CHECK {
      misc_path /etc/keepalived/healthz.sh
    }
  }

  real_server 10.240.80.12 6443 {
    weight 1
    MISC_CHECK {
      misc_path /etc/keepalived/healthz.sh
    }
  }
}

virtual_server 10.240.80.100 80 {
  delay_loop 10
  lb_algo wrr
  lb_kind DR
  persistence_timeout 5
  protocol TCP

  real_server 10.240.80.10 80 {
    weight 1
    TCP_CHECK {
      connect_timeout 3
    }
  }

  real_server 10.240.80.11 80 {
    weight 1
    TCP_CHECK {
      connect_timeout 3
    }
  }

  real_server 10.240.80.12 80 {
    weight 1
    TCP_CHECK {
      connect_timeout 3
    }
  }
}
</code></pre>

#### 
Reload systemd and start service

```
sudo systemctl daemon-reload
sudo systemctl enable keepalived
sudo systemctl start keepalived
systemctl status keepalived
```

### Healthcheck for https endpoint

```
cat <<EOF | sudo tee /etc/keepalived/healthz.sh
#!/bin/bash
# "curl --cacert ./ca.pem https://10.240.70.10:6443/healthz"  == "ok"
OK="$(curl -s -k https://10.240.70.10:6443/healthz --cacert /etc/keepalived/ca.pem)"
if [ $OK=="ok" ]; then
 exit 0
else 
 exit 1
fi
```


## Create Image for nameservers using PowerDNS
We will be using [CentOS cloud images](https://cloud-images.ubuntu.com) to build a base image for PowerDNS. Similar to the base image for Keepalived, we will do a lot of the preparation by using [cloud-init](https://cloud-init.io/). We will also leverage the CentOS [cloud images](https://cloud.centos.org/centos/7/images/) repository.

```
cd ~/tmp/downloads
wget https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2
cp CentOS-7-x86_64-GenericCloud.qcow2 /home/tmp/backingImages/powerdns.qcow2
```

### Install VM
#### Create base image to save as template for PowerDNS VMs
<pre><code>
for i in user-data meta-data network-config; do
  if [ -f ${i} ]; 
    then rm ${i};
  fi
  cp bak/${i}.cnt ${i};
done;

sed -i "s?controller?powerdns?" user-data
sed -i -e "s?instance00?powerdns?" -e "s?initial?powerdns?" meta-data
sed -i -e "s?.60?.80?" network-config
  
genisoimage  -output /vm/tmp/iso/powerdns.iso -volid cidata -joliet -rock user-data meta-data network-config
cp /vm/tmp/backingImage/CentOS-7-base.qcow2 /vm/tmp/images/powerdns.qcow2
qemu-img resize /vm/tmp/backingImage/powerdns.qcow2 40G

## Compute Instance
virt-install --name powerdns \
  --ram=2048 --vcpus=1 --cpu host --hvm \
  --disk path=/vm/tmp/images/powerdns.qcow2 \
  --import --disk path=/vm/tmp/iso/powerdns.iso,device=cdrom \
  --network bridge=enp7,model=virtio,virtualport_type=openvswitch \
  --console pty,target_type=virtio --os-variant=centos7.0 --noautoconsole &
</code></pre>

### We will add the required repositories to enable us install the various applications required. 
<code><pre>
sudo -s
vi /etc/yum.repos.d/MariaDB.repo
</code></pre>

#### Add the lines below to add MariaDB 10.3 (CentOS repository list - created 2019-05-19 22:29 UTC) [mariadb repo](http://downloads.mariadb.org/mariadb/repositories/)

<code><pre>
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.3/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
</code></pre>

<code><pre>
sudo curl -o /etc/yum.repos.d/powerdns-auth-42.repo https://repo.powerdns.com/repo-files/centos-auth-42.repo
sudo curl -o /etc/yum.repos.d/powerdns-rec-42.repo https://repo.powerdns.com/repo-files/centos-rec-42.repo
sudo curl -o /etc/yum.repos.d/powerdns-dnsdist-14.repo https://repo.powerdns.com/repo-files/centos-dnsdist-14.repo
yes | sudo curl -sL https://rpm.nodesource.com/setup_10.x | sudo bash -
yes | sudo curl -sL https://dl.yarnpkg.com/rpm/yarn.repo -o /etc/yum.repos.d/yarn.repo
yes | sudo curl -o /etc/yum.repos.d/powerdns-auth-42.repo https://repo.powerdns.com/repo-files/centos-auth-42.repo
sudo yum update -y
sudo yum install -y epel-release yum-plugin-priorities https://centos7.iuscommunity.org/ius-release.rpm centos-release-gluster
sudo yum update -y
</code></pre>

<code><pre>
sudo yum install -y pdns-backend-mysql python36u python36u-devel python36u-pip gcc yarn git uwsgi uwsgi-plugin-python2 nginx MariaDB-server MariaDB-client pdns pdns-recursor dnsdist gcc MariaDB-devel MariaDB-shared openldap-devel xmlsec1-devel xmlsec1-openssl libtool-ltdl-devel glusterfs-server
</code></pre>

<code><pre>
sudo pip3.6 install -U pip
sudo pip3.6 install -U virtualenv
sudo rm -f /usr/bin/python3
sudo ln -s /usr/bin/python3.6 /usr/bin/python3
</code></pre>

We will then run cloud-init clean to clean the slate so that subsequent VM will run cloud-init, shutdown the VM and remove the domain from libvirt

<code><pre>
sudo cloud-init clean
sudo shutdown -h now
virsh undefine powerdns
</code></pre>

#### Configure PowerDNS VMs (3 VMs in total for 3 nameservers)
<pre><code>
for i in user-data meta-data network-config; do
  if [ -f ${i} ]; 
    then rm ${i};
  fi
  cp bak/${i}.cnt ${i};
done;

for i in 1 2 3; do
  sed -i "s?controller?powerdns-${i}?" user-data
  sed -i -e "s?instance00?powerdns-${i}?" -e "s?initial?powerdns-${i}?" meta-data
  sed -i -e "s?.60?.8${i}?" network-config
  
  genisoimage  -output /vm/tmp/iso/powerdns-${i}.iso -volid cidata -joliet -rock user-data meta-data network-config
  qemu-img create -f qcow2 -o backing_file=/vm/tmp/backingImage/powerdns.qcow2 /vm/tmp/images/powerdns-${i}.img 40G
  qemu-img create -f qcow2 /vm/tmp/images/powerdns-hd2-${i}.img 5G
  
  rm user-data meta-data network-config
  for j in user-data meta-data network-config; do
    cp bak/${j}.cnt ${j};
  done;
done

## Compute Instance
for i in 1 2 3; do
  virt-install --name powerdns-${i} \
    --ram=2048 --vcpus=1 --cpu host --hvm \
    --disk path=/vm/tmp/images/powerdns-${i}.img \
    --disk path=/vm/tmp/images/powerdns-hd2-${i}.img \
    --import --disk path=/vm/tmp/iso/powerdns-${i}.iso,device=cdrom \
    --network bridge=enp7,model=virtio,virtualport_type=openvswitch \
    --console pty,target_type=virtio --os-variant=centos7.0 --noautoconsole &
done
</code></pre>

#### Create Mount Point for GlusterFS Volume - We will use our second hard drive for the GlusterFS volume
sudo mkdir -p /media/glusterfs
sudo chown $USER:$USER -R /media/glusterfs

#### Create Partition and Volume for GlusterFS
```
sudo fdisk -l
sudo fdisk /dev/sdb
```

Choose the following options:
```
n
p
1
2048
default
w
```

```
sudo mkfs.ext4 /dev/sdb1
sudo mount /dev/sdb1 /media/glusterfs
sudo vi /etc/fstab
```

Add the following line to `fstab`

`/dev/sdb1   /media/glusterfs    ext4    defaults    0   0`

#### Create GlusterFS
##### Edit /etc/hosts - Since we don't have our nameservers up and running yet, we will add the following entries to our host file to enable the systems to find eachother using hostnames

`sudo vi /etc/hosts`

Add the following lines to the host file

```
10.240.70.81    powerdns-1.homelab.test   powerdns-1
10.240.70.82    powerdns-2.homelab.test   powerdns-2
10.240.70.83    powerdns-3.homelab.test   powerdns-3
```

```
sudo systemctl enable glusterd
sudo systemctl start glusterd
systemctl status glusterd
```

#### From PowerDNS-1
```
sudo gluster peer probe powerdns-2
sudo gluster peer probe powerdns-3
```

#### From PowerDNS-2
```
sudo gluster peer probe powerdns-1
sudo gluster peer status
```

We will then create a gluster volume. We are doing this since we want highly available nameservers. The frontend to PowerDNS will be served from the Gluster volume.

```
sudo gluster volume create www replica 3 powerdns-1:/media/glusterfs/ \
powerdns-2:/media/glusterfs/ powerdns-3:/media/glusterfs/ force
sudo gluster volume start www
sudo gluster volume info

mkdir /home/dude/glusterFS
sudo mount -t glusterfs powerdns-1:www /home/dude/glusterFS
sudo mount -t glusterfs powerdns-2:www /home/dude/glusterFS
sudo mount -t glusterfs powerdns-3:www /home/dude/glusterFS
```

#### Configure automount gluster volume
```
sudo vi /etc/fstab
powerdns-1:www  /home/dude/glusterFS   glusterfs   defaults,_netdev,noauto,x-systemd.automount 0 0

powerdns-2:www  /home/dude/glusterFS   glusterfs   defaults,_netdev,noauto,x-systemd.automount 0 0

powerdns-3:www  /home/dude/glusterFS   glusterfs   defaults,_netdev,noauto,x-systemd.automount 0 0
```

We will be turning off SELinux (this is not advisable in production). We will update the guide later on to show how to enable SELinux after granting our applications permissions. We will also start our database and use the secure configuration wizard to ensure we have the recommending settings applied.
```
sudo setenforce 0
sudo systemctl start mariadb
sudo mysql_secure_installation
sudo systemctl stop mariadb
```

The database holding the name entries will also be made highly available using galera to handle replication. We will need to add the necessary configuration to allow this.

```
sudo mv /etc/my.cnf.d/server.cnf /etc/my.cnf.d/server.cnf.backup
####sudo vi /etc/my.cnf.d/server.cnf
```


```
cat <<EOF | sudo tee /etc/my.cnf.d/server.cnf
[galera]
# Mandatory settings
wsrep_on=ON
wsrep_provider=/usr/lib64/galera/libgalera_smm.so
wsrep_cluster_address="gcomm://10.240.70.81,10.240.70.82,10.240.70.83"
wsrep_sst_method=rsync
wsrep_node_address="10.240.70.83"
wsrep_node_name="pdns-3"
binlog_format=row
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
EOF
```


#### Start Galera cluster
```
sudo galera_new_cluster
sudo systemctl start mariadb.service
```

Check the status of the cluster
`mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size'"`


#### Create Database for PowerDNS and PowerDNS-Admin
mysql -u root -p

```
#Database for PowerDNS
CREATE DATABASE pdns;

USE pdns;

CREATE TABLE domains (
  id                    INT AUTO_INCREMENT,
  name                  VARCHAR(255) NOT NULL,
  master                VARCHAR(128) DEFAULT NULL,
  last_check            INT DEFAULT NULL,
  type                  VARCHAR(6) NOT NULL,
  notified_serial       INT UNSIGNED DEFAULT NULL,
  account               VARCHAR(40) CHARACTER SET 'utf8' DEFAULT NULL,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE UNIQUE INDEX name_index ON domains(name);


CREATE TABLE records (
  id                    BIGINT AUTO_INCREMENT,
  domain_id             INT DEFAULT NULL,
  name                  VARCHAR(255) DEFAULT NULL,
  type                  VARCHAR(10) DEFAULT NULL,
  content               VARCHAR(64000) DEFAULT NULL,
  ttl                   INT DEFAULT NULL,
  prio                  INT DEFAULT NULL,
  disabled              TINYINT(1) DEFAULT 0,
  ordername             VARCHAR(255) BINARY DEFAULT NULL,
  auth                  TINYINT(1) DEFAULT 1,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX nametype_index ON records(name,type);
CREATE INDEX domain_id ON records(domain_id);
CREATE INDEX ordername ON records (ordername);


CREATE TABLE supermasters (
  ip                    VARCHAR(64) NOT NULL,
  nameserver            VARCHAR(255) NOT NULL,
  account               VARCHAR(40) CHARACTER SET 'utf8' NOT NULL,
  PRIMARY KEY (ip, nameserver)
) Engine=InnoDB CHARACTER SET 'latin1';


CREATE TABLE comments (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  name                  VARCHAR(255) NOT NULL,
  type                  VARCHAR(10) NOT NULL,
  modified_at           INT NOT NULL,
  account               VARCHAR(40) CHARACTER SET 'utf8' DEFAULT NULL,
  comment               TEXT CHARACTER SET 'utf8' NOT NULL,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX comments_name_type_idx ON comments (name, type);
CREATE INDEX comments_order_idx ON comments (domain_id, modified_at);


CREATE TABLE domainmetadata (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  kind                  VARCHAR(32),
  content               TEXT,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX domainmetadata_idx ON domainmetadata (domain_id, kind);


CREATE TABLE cryptokeys (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  flags                 INT NOT NULL,
  active                BOOL,
  content               TEXT,
  PRIMARY KEY(id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX domainidindex ON cryptokeys(domain_id);


CREATE TABLE tsigkeys (
  id                    INT AUTO_INCREMENT,
  name                  VARCHAR(255),
  algorithm             VARCHAR(50),
  secret                VARCHAR(255),
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE UNIQUE INDEX namealgoindex ON tsigkeys(name, algorithm);

ALTER TABLE records ADD CONSTRAINT `records_domain_id_ibfk` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE comments ADD CONSTRAINT `comments_domain_id_ibfk` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE domainmetadata ADD CONSTRAINT `domainmetadata_domain_id_ibfk` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE cryptokeys ADD CONSTRAINT `cryptokeys_domain_id_ibfk` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

GRANT ALL ON pdns.* TO 'pdns'@'localhost' IDENTIFIED BY 'fisayoj';



# Database for PowerDNS-Admin
CREATE DATABASE powerdnsadmin CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON powerdnsadmin.* TO 'pdnsadminuser'@'%' IDENTIFIED BY 'fisayoj';
FLUSH PRIVILEGES;
quit 

USE powerdnsadmin;
ALTER TABLE history MODIFY detail MEDIUMTEXT;
```

#### Configure PowerDNS Authoritative Server
```
cd /etc/pdns/
sudo mv pdns.conf pdns.conf.backup
~~sudo scp dude@10.240.10.254:/vm/tmp/bak/pdns.conf .~~
```


```
cat <<EOF | sudo tee /etc/pdns/pdns.conf
launch=gmysql
gmysql-host=localhost
gmysql-dbname=pdns
gmysql-user=pdns
gmysql-password=Passw0rd!
webserver=yes
webserver-address=0.0.0.0
webserver-allow-from=0.0.0.0/0
webserver-port=8080
api=yes
api-key=2b2aec33-788a-4c86-ac4c-1d6d37fc0518
local-port=5300
default-soa-name=powerdns-1.homelab.test
EOF

```

```
sudo systemctl enable pdns
sudo systemctl start pdns
systemctl status pdns
```

#### Install PowerDNS frontend
```
mkdir -p /home/dude/glusterFS/powerdns-admin /home/dude/run/powerdns-admin
sudo chown -R $USER:$USER /home/dude/glusterFS
sudo git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git /home/dude/glusterFS/powerdns-admin
```

```
cd /home/dude/glusterFS/powerdns-admin
virtualenv -p python3 flask
. ./flask/bin/activate
pip install python-dotenv
pip install -r requirements.txt
```

~~scp dude@10.240.10.254:/vm/tmp/bak/config.py .~~
```
cat <<EOF | sudo tee /home/$USER/glusterFS/powerdns-admin/config.py
import os
basedir = os.path.abspath(os.path.dirname(__file__))

# BASIC APP CONFIG
SECRET_KEY = 'ef99d8c0-e87e-4b1e-90b5-6598f990d8b1'
BIND_ADDRESS = '0.0.0.0'
PORT = 9191

# TIMEOUT - for large zones
TIMEOUT = 10

# LOG CONFIG
#  	- For docker, LOG_FILE=''
LOG_LEVEL = 'DEBUG'
LOG_FILE = 'logfile.log'
SALT = '$2b$12$yLUMTIfl21FKJQpTkRQXCu'

# UPLOAD DIRECTORY
UPLOAD_DIR = os.path.join(basedir, 'upload')

# DATABASE CONFIG
SQLA_DB_USER = 'pdnsadminuser'
SQLA_DB_PASSWORD = 'Passw0rd'
SQLA_DB_HOST = 'localhost'
SQLA_DB_PORT = 3306
SQLA_DB_NAME = 'powerdnsadmin'
SQLALCHEMY_TRACK_MODIFICATIONS = True

# DATABASE - MySQL
SQLALCHEMY_DATABASE_URI = 'mysql://'+SQLA_DB_USER+':'+SQLA_DB_PASSWORD+'@'+SQLA_DB_HOST+':'+str(SQLA_DB_PORT)+'/'+SQLA_DB_NAME

# DATABASE - SQLite
# SQLALCHEMY_DATABASE_URI = 'sqlite:///' + os.path.join(basedir, 'pdns.db')

# SAML Authentication
SAML_ENABLED = False
SAML_DEBUG = True
SAML_PATH = os.path.join(os.path.dirname(__file__), 'saml')
##Example for ADFS Metadata-URL
SAML_METADATA_URL = 'https://<hostname>/FederationMetadata/2007-06/FederationMetadata.xml'
#Cache Lifetime in Seconds
SAML_METADATA_CACHE_LIFETIME = 1

# SAML SSO binding format to use
## Default: library default (urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect)
#SAML_IDP_SSO_BINDING = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'

## EntityID of the IdP to use. Only needed if more than one IdP is
##   in the SAML_METADATA_URL
### Default: First (only) IdP in the SAML_METADATA_URL
### Example: https://idp.example.edu/idp
#SAML_IDP_ENTITY_ID = 'https://idp.example.edu/idp'
## NameID format to request
### Default: The SAML NameID Format in the metadata if present,
###   otherwise urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified
### Example: urn:oid:0.9.2342.19200300.100.1.1
#SAML_NAMEID_FORMAT = 'urn:oid:0.9.2342.19200300.100.1.1'

## Attribute to use for Email address
### Default: email
### Example: urn:oid:0.9.2342.19200300.100.1.3
#SAML_ATTRIBUTE_EMAIL = 'urn:oid:0.9.2342.19200300.100.1.3'

## Attribute to use for Given name
### Default: givenname
### Example: urn:oid:2.5.4.42
#SAML_ATTRIBUTE_GIVENNAME = 'urn:oid:2.5.4.42'

## Attribute to use for Surname
### Default: surname
### Example: urn:oid:2.5.4.4
#SAML_ATTRIBUTE_SURNAME = 'urn:oid:2.5.4.4'

## Split into Given name and Surname
## Useful if your IDP only gives a display name
### Default: none
### Example: http://schemas.microsoft.com/identity/claims/displayname
#SAML_ATTRIBUTE_NAME = 'http://schemas.microsoft.com/identity/claims/displayname'

## Attribute to use for username
### Default: Use NameID instead
### Example: urn:oid:0.9.2342.19200300.100.1.1
#SAML_ATTRIBUTE_USERNAME = 'urn:oid:0.9.2342.19200300.100.1.1'

## Attribute to get admin status from
### Default: Don't control admin with SAML attribute
### Example: https://example.edu/pdns-admin
### If set, look for the value 'true' to set a user as an administrator
### If not included in assertion, or set to something other than 'true',
###  the user is set as a non-administrator user.
#SAML_ATTRIBUTE_ADMIN = 'https://example.edu/pdns-admin'

## Attribute to get group from
### Default: Don't use groups from SAML attribute
### Example: https://example.edu/pdns-admin-group
#SAML_ATTRIBUTE_GROUP = 'https://example.edu/pdns-admin'

## Group namem to get admin status from
### Default: Don't control admin with SAML group
### Example: https://example.edu/pdns-admin
#SAML_GROUP_ADMIN_NAME = 'powerdns-admin'

## Attribute to get group to account mappings from
### Default: None
### If set, the user will be added and removed from accounts to match
###  what's in the login assertion if they are in the required group
#SAML_GROUP_TO_ACCOUNT_MAPPING = 'dev-admins=dev,prod-admins=prod'

## Attribute to get account names from
### Default: Don't control accounts with SAML attribute
### If set, the user will be added and removed from accounts to match
###  what's in the login assertion. Accounts that don't exist will
###  be created and the user added to them.
SAML_ATTRIBUTE_ACCOUNT = 'https://example.edu/pdns-account'

SAML_SP_ENTITY_ID = 'http://<SAML SP Entity ID>'
SAML_SP_CONTACT_NAME = '<contact name>'
SAML_SP_CONTACT_MAIL = '<contact mail>'
#Configures if SAML tokens should be encrypted.
#If enabled a new app certificate will be generated on restart
SAML_SIGN_REQUEST = False

# Configures if you want to request the IDP to sign the message
# Default is True
#SAML_WANT_MESSAGE_SIGNED = True

#Use SAML standard logout mechanism retrieved from idp metadata
#If configured false don't care about SAML session on logout.
#Logout from PowerDNS-Admin only and keep SAML session authenticated.
SAML_LOGOUT = False
#Configure to redirect to a different url then PowerDNS-Admin login after SAML logout
#for example redirect to google.com after successful saml logout
#SAML_LOGOUT_URL = 'https://google.com'
EOF
```

`export FLASK_APP=app/__init__.py`

#### Run db upgrade on only one node
`flask db upgrade`

*Run "ALTER table from database file: pdns.sql"*

~~# mysql -u root -p~~

```
yarn install --pure-lockfile
flask assets build
./run.py
```

#### NGINX - Create Systemd Service file
~~sudo scp dude@10.240.10.254:/vm/tmp/bak/powerdns-admin.service /etc/systemd/system/~~
```
cat <<EOF | sudo tee /etc/systemd/system/powerdns-admin.service
[Unit]
Description=PowerDNS-Admin
After=network.target

[Service]
WorkingDirectory=/home/dude/glusterFS/powerdns-admin
Environment="PATH=/home/dude/glusterFS/powerdns-admin"
ExecStart=/home/dude/glusterFS/powerdns-admin/flask/bin/gunicorn --workers 3 --bind unix:/home/dude/run/powerdns-admin/powerdns-admin.sock run:app

[Install]
WantedBy=multi-user.target
EOF
```


```
sudo systemctl daemon-reload
sudo systemctl enable powerdns-admin.service
sudo systemctl start powerdns-admin.service
systemctl status powerdns-admin
```

#### Work around nginx
`sudo mkdir /etc/systemd/system/nginx.service.d`
~~sudo vi /etc/systemd/system/nginx.service.d/override.conf~~
```
cat <<EOF | sudo tee /etc/systemd/system/nginx.service.d/override.conf
[Service]
ExecStartPost=/bin/sleep 0.1
```

~~ printf "[Service]\nExecStartPost=/bin/sleep 0.1\n" > /etc/systemd/system/nginx.service.d/override.conf~~

```
sudo systemctl daemon-reload
sudo systemctl restart nginx
systemctl status nginx
```

#### Create Nginx configuration file
Remember to change the user and the IP address in the config

`sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak`

~~sudo scp dude@10.240.10.254:/vm/tmp/bak/powerdns-admin-nginx /etc/nginx/nginx.conf~~
```
cat <<EOF | sudo tee /etc/nginx/nginx.conf
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user dude;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/nginx/README.dynamic.
# include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;

server {
  listen 			80;
  server_name			10.240.70.81;

  index				index.html index.htm index.php;
  root				/home/dude/glusterFS/powerdns-admin;
  access_log			/var/log/nginx/powerdns-admin.local.access.log combined;
  error_log                 	/var/log/nginx/powerdns-admin.local.error.log;

  client_max_body_size			10m;
  client_body_buffer_size		128k;
  proxy_redirect			off;
  proxy_connect_timeout			90;
  proxy_send_timeout			90;
  proxy_read_timeout			90;
  proxy_buffers				32 4k;
  proxy_buffer_size			8k;
  proxy_set_header			Host $host;
  proxy_set_header			X-Real-IP $remote_addr;
  proxy_set_header			X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_headers_hash_bucket_size	64;

  location ~ ^/static/ {
    include /etc/nginx/mime.types;
    root /home/dude/glusterFS/powerdns-admin/app;

    location ~* \.(jpg|jpeg|png|gif)$ {
      expires 365d;
    }

    location ~* ^.+.(css|js)$ {
      expires 7d;
    }
  }
 
  location / {
    proxy_pass				http://unix:/home/dude/run/powerdns-admin/powerdns-admin.sock;
    proxy_read_timeout			120;
    proxy_connect_timeout		120;
    proxy_redirect			off;
  }
}
}
EOF
```

#### Check the configuration and then restart nginx
```
sudo nginx -t
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx
systemctl status nginx
```

~~# sudo mkdir -p /etc/nginx/sites-available/ /etc/nginx/sites-enabled~~

~~# sudo ln -s /etc/nginx/sites-available/powerdns-admin-nginx /etc/nginx/sites-enabled~~


#### Create PowerDNS recursor configuration file -
Edit the IP address to match local IP

`sudo mv /etc/pdns-recursor/recursor.conf /etc/pdns-recursor/recursor.conf.backup`

~~sudo scp dude@10.240.10.254:/vm/tmp/bak/recursor.conf /etc/pdns-recursor/recursor.conf~~

~~sudo vi /etc/pdns-recursor/recursor.conf~~

```
cat <<EOF | sudo tee /etc/pdns-recursor/recursor.conf
local-address=10.240.70.84
allow-from=127.0.0.0/8,10.0.0.0/8,192.168.0.0/16
forward-zones-recurse=.=1.1.1.1,.=9.9.9.9
local-port=5301
EOF
```

```
sudo systemctl stop pdns-recursor
sudo systemctl enable pdns-recursor
sudo systemctl start pdns-recursor
```

#### Create PowerDNS dnsdist configuration file

`sudo mv /etc/dnsdist/dnsdist.conf /etc/dnsdist/dnsdist.conf.backup`

~~sudo scp dude@10.240.10.254:/vm/tmp/bak/dnsdist.conf /etc/dnsdist/dnsdist.conf~~

~~sudo vi /etc/dnsdist/dnsdist.conf~~

```
cat <<EOF | sudo tee /etc/dnsdist/dnsdist.conf
setLocal("10.240.70.81")

newServer({address="10.240.70.81:5300",name="powerdns-1",pool="auth"})
newServer({address="10.240.70.82:5300",name="powerdns-2",pool="auth"})
newServer({address="10.240.70.83:5300",name="powerdns-3",pool="auth"})

newServer({address="10.240.70.81:5301",name="powerdns-1",pool="rec"})
newServer({address="10.240.70.82:5301",name="powerdns-2",pool="rec"})
newServer({address="10.240.70.83:5301",name="powerdns-3",pool="rec"})

customerACLs={"198.168.0.0/16", "10.0.0.0/8"}

addAction("homelab.test.", PoolAction("auth"))
addAction(RDRule(), PoolAction("rec"))
webserver("0.0.0.0:8000", "Passw0rd!", "2b2aec33-788a-4c86-ac4c-1d6d37fc0518")
EOF
```

```
sudo systemctl enable dnsdist
sudo systemctl start dnsdist
systemctl status dnsdist
```

#### Test ports
`nc -vzu`


~~#### Configure SELinux~~
~~sudo fgrep "mysqld" /var/log/audit/audit.log | sudo audit2allow -m MySQL_galera -o MySQL_galera.te~~
~~sudo checkmodule -M -m MySQL_galera.te -o MySQL_galera.mod~~
~~sudo semodule_package -m MySQL_galera.mod -o MySQL_galera.pp~~
~~sudo semodule -i MySQL_galera.pp~~
~~# sudo setenforce 1~~
~~sudo systemctl restart mariadb~~
~~sudo systemctl status mariadb~~

At this point we should have our support infrastructure installed and configured. Our nameservers listening and the loadbalancers failing checks since there are no services yet. We will now proceed with installing the controller and worker nodes


Next: [Compute Resources](04-compute-resources.md)
