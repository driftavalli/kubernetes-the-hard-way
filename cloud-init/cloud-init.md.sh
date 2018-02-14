rm network-config
rm meta-data
rm user-data
cp bak/network-config.bak network-config
cp bak/meta-data.bak meta-data
cp bak/user-data.bak user-data
printf "packages:\n  - bind9\n  - bind9utils\n  - bind9-doc]" >> user-data


## Create Images
for i in 1 2; do
  sed -i "s?controller?dns-${i}?" user-data
  sed -i -e "s?instance00?dns${i}?" -e "s?initial?dns-${i}?" meta-data
  sed -i "s?.60?.3${i}?" network-config
  genisoimage  -output seeddns-${i}.iso -volid cidata -joliet -rock user-data meta-data network-config
  rm user-data meta-data network-config
  cp bak/network-config.bak network-config
  cp bak/meta-data.bak meta-data
  cp bak/user-data.bak user-data
  printf "packages:\n  - bind9\n  - bind9utils\n  - bind9-doc]" >> user-data
  qemu-img create -f qcow2 -b  xenial-server-cloudimg-amd64-disk1.img dns-${i}.img 40G
done

rm network-config
rm meta-data
rm user-data
cp bak/network-config.bak network-config
cp bak/meta-data.bak meta-data
cp bak/user-data.bak user-data

## Create Images
for i in 1 2; do
  sed -i "s?controller?loadbalancer-${i}?" user-data
  sed -i -e "s?instance00?lb0${i}?" -e "s?initial?loadbalancer-${i}?" meta-data
  sed -i -e "s?.60?.4${i}?" -e "s?kvm?loadbalancer-${i}?" network-config
  genisoimage  -output seedLoadbalancer-${i}.iso -volid cidata -joliet -rock user-data meta-data network-config
  rm user-data meta-data network-config
  cp bak/user-data.bak user-data
  cp bak/meta-data.bak meta-data
  cp bak/network-config.bak network-config
  qemu-img create -f qcow2 -b  xenial-server-cloudimg-amd64-disk1.img Loadbalancer-${i}.img 40G
done

rm network-config
rm meta-data
rm user-data
cp bak/network-config.bak network-config
cp bak/meta-data.bak meta-data
cp bak/user-data.bak user-data

## Create the worker nocloud source and backing img
for i in 0 1 2; do
  sed -i "s?controller?worker-${i}?" user-data
  sed -i -e "s?instance00?localW${i}?" -e "s?initial?worker-${i}?" meta-data
  sed -i -e "s?.60?.7${i}?" -e "s?host?worker-${i}?" network-config
  genisoimage  -output WorkerKube${i}.iso -volid cidata -joliet -rock user-data meta-data network-config
  rm user-data meta-data network-config
  cp bak/user-data.bak user-data
  cp bak/meta-data.bak meta-data
  cp bak/network-config.bak network-config
  qemu-img create -f qcow2 -b  xenial-server-cloudimg-amd64-disk1.img worker-${i}.img 40G
done

rm network-config
rm meta-data
rm user-data
cp bak/network-config.bak network-config
cp bak/meta-data.bak meta-data
cp bak/user-data.bak user-data

## Create the controller nocloud source and backing img
for i in 0 1 2; do
  echo "write_files:
  - path: /etc/modprobe.d/dummy.conf
    content: options dummy numdummies=1
  - path: /etc/modules-load.d/dummy.conf
    content: dummy" >> user-data
  sed -i "s?controller?controller-${i}?" user-data
  sed -i -e "s?instance00?local0${i}?" -e "s?initial?controller-${i}?" meta-data
  sed -i -e "s?.60?.6${i}?" -e "s?host?controller-${i}?" network-config
  genisoimage  -output ControllerKube${i}.iso -volid cidata -joliet -rock user-data meta-data network-config
  rm user-data meta-data network-config
  cp bak/user-data.bak user-data
  cp bak/meta-data.bak meta-data
  cp bak/network-config.bak network-config
  echo
  qemu-img create -f qcow2 -b  xenial-server-cloudimg-amd64-disk1.img controller-${i}.img 40G
done
