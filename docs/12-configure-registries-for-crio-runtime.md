## Edit the crio configuration file to enable container registries

Uncomment the following lines in `/etc/containers/registries.conf` and `/etc/crio/crio.conf`. This needs to be done on all the compute instances

```
# List of registries to be used when pulling an unqualified image (e.g.,
# "alpine:latest"). By default, registries is set to "docker.io" for
# compatibility reasons. Depending on your workload and usecase you may add more
# registries (e.g., "quay.io", "registry.fedoraproject.org",
# "registry.opensuse.org", etc.).
registries = [
       "docker.io",
       "quay.io",
]
EOF
```
```
sudo systemctl restart crio
```

Next: [Deploying the DNS Cluster Add-on](13-dns-addon.md)