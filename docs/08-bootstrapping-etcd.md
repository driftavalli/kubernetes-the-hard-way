# Bootstrapping the etcd Cluster

Kubernetes components are stateless and store cluster state in [etcd](https://github.com/coreos/etcd). In this lab you will bootstrap a three node etcd cluster and configure it for high availability and secure remote access.

## Prerequisites

The commands in this lab must be run on each controller instance: `controller-0`, `controller-1`, and `controller-2`. Login to each controller instance using the `gcloud` command. Example:

```
gcloud compute ssh controller-0
```

## Bootstrapping an etcd Cluster Member

### Download and Install the etcd Binaries

Download the official etcd release binaries from the [coreos/etcd](https://github.com/coreos/etcd) GitHub project. To avoid downloading over and over, we will download one time and copy to the controllers.

```
wget -q --show-progress --https-only --timestamping \
  "https://github.com/coreos/etcd/releases/download/v3.3.9/etcd-v3.3.9-linux-amd64.tar.gz"
```

We will define a variable CONTROLLER LIST
```
CONTROLLER_LIST=(
  controller-0
  controller-1
  controller-2
)
```

```
for instance in "${CONTROLLER_LIST[@]}"; do
 scp etcd-v3.3.9-linux-amd64.tar.gz ${instance}:~/
done
```

Extract and install the `etcd` server and the `etcdctl` command line utility:

```
tar -xvf etcd-v3.3.9-linux-amd64.tar.gz
```

```
sudo mv etcd-v3.3.9-linux-amd64/etcd* /usr/local/bin/
```

### Configure the etcd Server

```
sudo mkdir -p /etc/etcd /var/lib/etcd
```

```
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
```

The instance internal IP address will be used to serve client requests and communicate with etcd cluster peers. Retrieve the internal IP address for the current compute instance:

```
INTERNAL_IP=$(dig +short $HOSTNAME)
```

Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current compute instance:

```
ETCD_NAME=$(hostname -s)
```

Create the `etcd.service` systemd unit file:

```
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
NotifyAccess=main
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-0=https://10.240.70.10:2380,controller-1=https://10.240.70.11:2380,controller-2=https://10.240.70.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Start the etcd Server

```
sudo mv etcd.service /etc/systemd/system/
```

```
sudo systemctl daemon-reload
```

```
sudo systemctl enable etcd
```

```
sudo systemctl start etcd
```

> Remember to run the above commands on each controller node: `controller-0`, `controller-1`, and `controller-2`.

## Verification

List the etcd cluster members:

```
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

> output

```
1f8c1c6787d25101, started, controller-0, https://10.240.70:2380, https://10.240.70:2379
7359009093bb67dd, started, controller-1, https://10.240.71:2380, https://10.240.71:2379
8853c4471044d538, started, controller-2, https://10.240.72:2380, https://10.240.72:2379
```

Next: [Bootstrapping the Kubernetes Control Plane](09-bootstrapping-kubernetes-controllers.md)
