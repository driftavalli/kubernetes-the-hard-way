# Infrastructure setup
## Install KVM
We'll be using KVM as the hypervisor. Installation of KVM won't be covered here as there are lots of good articles that describe how to do that. Check [KVM Installation](https://help.ubuntu.com/community/KVM/Installation) for how to get started.

## Create bridge
We will configure our nic to act as a bridge to which we will connect the VMs to. This allows the possibility of running multiple clusters on the same machine. The config below is how the server has been setup however the network configuration to enable this is out of scope and won't be covered here. 

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
```
Then to activate the configuration, run

`sudo netplan generate`

`sudo netplan apply`

If everything is setup correctly, you should have a bridge assigned with a static IP.
## Create Base Image for installation of [Keepalived](http://www.keepalived.org)
* We will be using [Ubuntu cloud images](https://cloud-images.ubuntu.com) to build a base image for Keepalived. Download the image for [Ubuntu 18.04 LTS (Bionic Beaver)](https://cloud-images.ubuntu.com/bionic/current/).

    `wget https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img`

* Install the VM

Ubuntu does not have the most recent version of Keepalived so we will download the tar and install the latest version

## [Get Latest version of Keepalived](http://www.keepalived.org/download.html)
```
curl --progress http://keepalived.org/software/keepalived-1.2.15.tar.gz | tar xz
cd keepalived-1.2.15
./configure --prefix=/usr/local/keepalived-1.2.15
make
sudo make install
ln -s /usr/local/keepalived-1.2.15 /usr/local/keepalived
vim ~/.profile
export PATH=$PATH:/usr/local/keepalived/sbin
```
Add the following line to sysctl.conf (`sudo vim /etc/sysctl.conf`)

`net.ipv4.ip_forward = 1`

This enables ip forwarding on the VM. See []() for other options

### Create systemd service file
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

```
sudo systemctl daemon-reload
sudo systemctl enable keepalived
sudo systemctl start keepalived
```

## Reset Cloud-Init
sudo cloud-init clean
sudo shutdown -h now
virt-sysprep -a keepalived.img

## Configure Keepalived
### LB-1
sudo scp dude@10.240.10.254:/vm/tmp/bak/keepalived.1 /etc/keepalived/keepalived.conf

### LB-2
sudo scp dude@10.240.10.254:/vm/tmp/bak/keepalived.2 /etc/keepalived/keepalived.conf

sudo vim /etc/keepalived/keepalived.conf
sudo systemctl restart keepalived

## Create repositories
sudo -s
vi /etc/yum.repos.d/MariaDB.repo

# MariaDB 10.3 CentOS repository list - created 2019-05-19 22:29 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.3/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1

sudo curl -o /etc/yum.repos.d/powerdns-auth-42.repo https://repo.powerdns.com/repo-files/centos-auth-42.repo
sudo curl -o /etc/yum.repos.d/powerdns-rec-42.repo https://repo.powerdns.com/repo-files/centos-rec-42.repo
sudo curl -o /etc/yum.repos.d/powerdns-dnsdist-14.repo https://repo.powerdns.com/repo-files/centos-dnsdist-14.repo
yes | sudo curl -sL https://rpm.nodesource.com/setup_10.x | sudo bash -
yes | sudo curl -sL https://dl.yarnpkg.com/rpm/yarn.repo -o /etc/yum.repos.d/yarn.repo
yes | sudo curl -o /etc/yum.repos.d/powerdns-auth-42.repo https://repo.powerdns.com/repo-files/centos-auth-42.repo

sudo yum update -y

sudo yum install -y epel-release yum-plugin-priorities https://centos7.iuscommunity.org/ius-release.rpm centos-release-gluster

sudo yum update -y

sudo yum install -y pdns-backend-mysql python36u python36u-devel python36u-pip \
gcc yarn git uwsgi uwsgi-plugin-python2 nginx MariaDB-server MariaDB-client \
pdns pdns-recursor dnsdist gcc MariaDB-devel MariaDB-shared openldap-devel \
xmlsec1-devel xmlsec1-openssl libtool-ltdl-devel glusterfs-server

sudo pip3.6 install -U pip
sudo pip3.6 install -U virtualenv
sudo rm -f /usr/bin/python3
sudo ln -s /usr/bin/python3.6 /usr/bin/python3

## To be used to create initial Image
## Remove "sudo virt-customize -a CentOS-7-base.qcow2 --edit "/etc/resolv.conf:s/^nameserver 10\.0\.2\.3//""

sudo cloud-init clean

virt-sysprep -a PowerDNS.qcow2

## Create Mount Point for GlusterFS Volume
sudo mkdir -p /media/glusterfs
sudo chown $USER:$USER -R /media/glusterfs

# Create Partition and Volume for GlusterFS
sudo fdisk -l
sudo fdisk /dev/sdb
n
p
1
2048
default
w
sudo mkfs.ext4 /dev/sdb1
sudo mount /dev/sdb1 /media/glusterfs
sudo vi /etc/fstab

/dev/sdb1   /media/glusterfs    ext4    defaults    0   0

## Create GlusterFS
### Edit /etc/hosts
sudo vi /etc/hosts

10.240.70.81    powerdns-1.homelab.test   powerdns-1
10.240.70.82    powerdns-2.homelab.test   powerdns-2
10.240.70.83    powerdns-3.homelab.test   powerdns-3

sudo systemctl enable glusterd
sudo systemctl start glusterd
systemctl status glusterd

### From PowerDNS-1
sudo gluster peer probe powerdns-2
sudo gluster peer probe powerdns-3

### From PowerDNS-2
sudo gluster peer probe powerdns-1

sudo gluster peer status

sudo gluster volume create www replica 3 powerdns-1:/media/glusterfs/ \
powerdns-2:/media/glusterfs/ powerdns-3:/media/glusterfs/ force
sudo gluster volume start www
sudo gluster volume info

mkdir /home/dude/glusterFS
sudo mount -t glusterfs powerdns-1:www /home/dude/glusterFS
sudo mount -t glusterfs powerdns-2:www /home/dude/glusterFS
sudo mount -t glusterfs powerdns-3:www /home/dude/glusterFS

# Configure automount gluster volume
sudo vi /etc/fstab
powerdns-1:www  /home/dude/glusterFS   glusterfs   defaults,_netdev,noauto,x-systemd.automount 0 0

powerdns-2:www  /home/dude/glusterFS   glusterfs   defaults,_netdev,noauto,x-systemd.automount 0 0

powerdns-3:www  /home/dude/glusterFS   glusterfs   defaults,_netdev,noauto,x-systemd.automount 0 0

# sudo firewall-cmd --permanent --add-service=mysql
# sudo firewall-cmd --permanent --add-port={4567,4568,4444,8080,9191}/tcp
# sudo firewall-cmd --reload
sudo setenforce 0

sudo systemctl start mariadb

sudo mysql_secure_installation

sudo systemctl stop mariadb

sudo mv /etc/my.cnf.d/server.cnf /etc/my.cnf.d/server.cnf.backup
sudo vi /etc/my.cnf.d/server.cnf

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

## Start Galera cluster
sudo galera_new_cluster
sudo systemctl start mariadb.service

mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size'"

# Create Database for PowerDNS and PowerDNS-Admin
mysql -u root -p

## Configure PowerDNS Authoritative Server
cd /etc/pdns/
sudo mv pdns.conf pdns.conf.backup
sudo scp dude@10.240.10.254:/vm/tmp/bak/pdns.conf .

sudo systemctl enable pdns
sudo systemctl start pdns
systemctl status pdns

# Install Web frontend
mkdir -p /home/dude/glusterFS/powerdns-admin /home/dude/run/powerdns-admin
sudo chown -R $USER:$USER /home/dude/glusterFS
sudo git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git /home/dude/glusterFS/powerdns-admin

cd /home/dude/glusterFS/powerdns-admin
virtualenv -p python3 flask
. ./flask/bin/activate
pip install python-dotenv
pip install -r requirements.txt
scp dude@10.240.10.254:/vm/tmp/bak/config.py .
export FLASK_APP=app/__init__.py
# Run db upgrade on only one node
flask db upgrade
# Run "ALTER table from database file: pdns.sql"
# mysql -u root -p

yarn install --pure-lockfile
flask assets build
./run.py

# NGINX 
# Create Systemd Service file
sudo scp dude@10.240.10.254:/vm/tmp/bak/powerdns-admin.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable powerdns-admin.service
sudo systemctl start powerdns-admin.service
systemctl status powerdns-admin

# Work around nginx
sudo mkdir /etc/systemd/system/nginx.service.d
sudo vi /etc/systemd/system/nginx.service.d/override.conf
[Service]
ExecStartPost=/bin/sleep 0.1

# printf "[Service]\nExecStartPost=/bin/sleep 0.1\n" > /etc/systemd/system/nginx.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart nginx
systemctl status nginx

# Create Nginx configuration file
sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
sudo scp dude@10.240.10.254:/vm/tmp/bak/powerdns-admin-nginx /etc/nginx/nginx.conf
sudo nginx -t
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx
systemctl status nginx

# sudo mkdir -p /etc/nginx/sites-available/ /etc/nginx/sites-enabled
# sudo ln -s /etc/nginx/sites-available/powerdns-admin-nginx /etc/nginx/sites-enabled

# Create PowerDNS recursor configuration file
sudo mv /etc/pdns-recursor/recursor.conf /etc/pdns-recursor/recursor.conf.backup
sudo scp dude@10.240.10.254:/vm/tmp/bak/recursor.conf /etc/pdns-recursor/recursor.conf
sudo vi /etc/pdns-recursor/recursor.conf
sudo systemctl stop pdns-recursor
sudo systemctl enable pdns-recursor
sudo systemctl start pdns-recursor

# Create PowerDNS dnsdist configuration file
sudo mv /etc/dnsdist/dnsdist.conf /etc/dnsdist/dnsdist.conf.backup
sudo scp dude@10.240.10.254:/vm/tmp/bak/dnsdist.conf /etc/dnsdist/dnsdist.conf
sudo vi /etc/dnsdist/dnsdist.conf
sudo systemctl enable dnsdist
sudo systemctl start dnsdist
systemctl status dnsdist

## Test ports
nc -vzu

########
# Configure SELinux
sudo fgrep "mysqld" /var/log/audit/audit.log | sudo audit2allow -m MySQL_galera -o MySQL_galera.te
sudo checkmodule -M -m MySQL_galera.te -o MySQL_galera.mod
sudo semodule_package -m MySQL_galera.mod -o MySQL_galera.pp
sudo semodule -i MySQL_galera.pp
# sudo setenforce 1
sudo systemctl restart mariadb
sudo systemctl status mariadb


Next: [Compute Resources](04-compute-resources.md)