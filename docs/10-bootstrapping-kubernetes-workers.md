# Bootstrapping the Kubernetes Worker Nodes

In this lab you will bootstrap three Kubernetes worker nodes. To avoid downloading over and over, we will download one time and copy to the controllers

We will define some variables
```
WORKER_LIST=(
  worker-0
  worker-1
  worker-2
)
```

```
WORKER_IP=(
  10.240.70.20
  10.240.70.21
  10.240.70.22
)
```

```
BINARIES=(
  kubectl \
  kube-proxy \
  kubelet
)
```

cd /home/$USER/projects/kubernetes/CKA/configFiles/downloads

```
for BINARY in ${BINARIES[@]}; do
if [ ! -f $BINARY ]; then 
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/${BINARY}" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/${BINARY}" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/${BINARY}"
fi
done
```

```
for instance in ${WORKER_LIST[@]}; do
  scp kubectl kube-proxy kubelet ${instance}:~/
done
```

### Provisioning a Kubernetes Worker Node

`cd /home/$USER/projects/kubernetes/CKA/configFiles/certs`

Create the kubelet-config.yaml configuration file:
```
for instance in "${WORKER_LIST[@]}"; do
cat <<EOF | tee kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
cgroupDriver: "systemd"
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${instance}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${instance}-key.pem"
EOF
scp kubelet-config.yaml ${instance}:~/
done
```

The resolvConf configuration is used to avoid loops when using CoreDNS for service discovery on systems running systemd-resolved.

Create the kubelet.service systemd unit file:
```
cat <<EOF | tee kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=crio.service
Requires=crio.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/crio/crio.sock \\
  --image-service-endpoint=unix:///var/run/crio/crio.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --cni-conf-dir=/etc/cni/net.d \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Create the kube-proxy-config.yaml configuration file:
```
cat <<EOF | tee kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "ipvs"
EOF
```

Create the kube-proxy.service systemd unit file:
```
cat <<EOF | tee kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Create the installation directories:
```
for instance in ${WORKER_LIST[@]}; do
scp kubelet.service kube-proxy-config.yaml kube-proxy.service ${instance}:~/
scp ${instance}-key.pem ${instance}.pem ${instance}.kubeconfig ca.pem kube-proxy.kubeconfig kube-proxy-config.yaml ${instance}:~/
ssh -T $instance <<EOF
sudo mkdir -p \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

## Install the worker binaries:
chmod +x kubectl kube-proxy kubelet
sudo mv kubectl kube-proxy kubelet /usr/local/bin/

## Configure the Kubelet
sudo mv kubelet-config.yaml /var/lib/kubelet/
sudo mv kubelet.service /etc/systemd/system/
sudo mv ${instance}-key.pem ${instance}.pem /var/lib/kubelet/
sudo mv ${instance}.kubeconfig /var/lib/kubelet/kubeconfig
sudo mv ca.pem /var/lib/kubernetes/

## Create the kube-proxy-config.yaml configuration file:
sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
sudo mv kube-proxy-config.yaml /var/lib/kube-proxy/
sudo mv kube-proxy.service /etc/systemd/system/

## Start the Worker Services
sudo systemctl daemon-reload
sudo systemctl enable kubelet kube-proxy
sudo systemctl start kubelet kube-proxy
sudo systemctl restart kubelet kube-proxy
EOF
done
```

### Verification

Login to one of the controller nodes:

```
ssh controller-0
```

List the registered Kubernetes nodes:

```
kubectl get nodes
```

> output

```
NAME       STATUS    ROLES     AGE       VERSION
worker-0   Ready     <none>    1m        v1.15.0
worker-1   Ready     <none>    1m        v1.15.0
worker-2   Ready     <none>    1m        v1.15.0
```

Next: [Configuring kubectl for Remote Access](11-configuring-kubectl.md)
