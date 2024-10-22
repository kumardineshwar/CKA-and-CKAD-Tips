#!/bin/bash
#

rm -f /tmp/setup_containerd.sh /tmp/setup_k8s.sh /tmp/node-join.sh /tmp/metallb-address-pool.yaml /tmp/lvm-storage-class.yaml

cat<<EOF>> /tmp/setup_containerd.sh
#!/bin/bash

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
modprobe br_netfilter

sudo sysctl --system
sysctl net.ipv4.ip_forward

sudo systemctl stop apparmor
sudo systemctl disable apparmor --now

apt-get install containerd -y

mkdir -p /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo sed -i 's/pause:3.8/pause:3.9/g' /etc/containerd/config.toml
crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock --set image-endpoint=unix:///run/containerd/containerd.sock
sudo systemctl daemon-reload
systemctl restart containerd.service

sudo apt-get install kubeadm kubelet kubernetes-cni -y

sleep 10
# create loopback device for the the CSI LVM
# sudo truncate -s 1024G /tmp/disk.img && sudo losetup -f /tmp/disk.img --show && sudo  pvcreate /dev/loop0 && sudo vgcreate lvmvg /dev/loop0

EOF

VERSION="v1.31.1"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz


for i in worker01 worker02 worker03; do scp /tmp/setup_containerd.sh $i:/tmp/setup_containerd.sh; done

for i in worker01 worker02 worker03; do scp /usr/local/bin/crictl $i:/usr/local/bin/crictl; done

for i in worker01 worker02 worker03 master01; do ssh $i "sh /tmp/setup_containerd.sh"; done

cat<<EOF>> /tmp/setup_k8s.sh
#!/bin/bash

IP=\$(ip a show ens33 | grep "192.168" | cut -d " " -f6 | cut -d"/" -f1)
HOST=\$(hostname)

kubeadm config images pull

apt-get install kubectl -y

kubeadm init --cri-socket /run/containerd/containerd.sock --apiserver-advertise-address \$IP --control-plane-endpoint \$IP --node-name \$HOST --v=7

export KUBECONFIG=/etc/kubernetes/admin.conf

kubeadm token create --print-join-command --ttl 0 2>/dev/null | tee /tmp/node-join.sh

mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
echo 'source <(kubectl completion bash)' >> /root/.bashrc


while [ \$(kubectl get nodes --no-headers | grep -c master01) -ne 1 ]; do sleep 10; done

sleep 30

kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

EOF

bash /tmp/setup_k8s.sh

sleep 10

for i in worker01 worker02 worker03; do scp /tmp/node-join.sh $i:/tmp/node-join.sh; done

for i in worker01 worker02 worker03; do ssh $i "sh /tmp/node-join.sh"; done

# wait for all 3 worker node to join
while [ $(kubectl get nodes --no-headers | grep -c worker) -ne 3 ]; do sleep 10; done


for i in worker01 worker02 worker03; do ssh $i "rm -f /tmp/setup_containerd.sh /tmp/node-join.sh"; done

# Clean UP

cp /tmp/node-join.sh node-join.sh

sleep 30

kubectl get nodes -o wide

wget https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml -O /tmp/metallb-native.yaml

kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | kubectl apply -f - -n kube-system

kubectl apply -f /tmp/metallb-native.yaml

cat<<EOF>>/tmp/metallb-address-pool.yaml
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.90.240-192.168.90.245

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: myl2adv
  namespace: metallb-system
EOF
sleep 60

kubectl apply -f /tmp/metallb-address-pool.yaml

for NODE in worker01 worker02 worker03
do
kubectl label node $NODE node-role.kubernetes.io/worker=
done

# Installing Helm.

curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y

helm version

rm -f /tmp/setup_containerd.sh /tmp/setup_k8s.sh /tmp/node-join.sh /tmp/metallb-address-pool.yaml 

sleep 5

# Installing OpenEBS for Persistance Storage using Helm.

helm repo add openebs https://openebs.github.io/openebs

helm repo update

helm install openebs --namespace openebs openebs/openebs --set engines.replicated.mayastor.enabled=false --set engines.local.zfs.enabled=false --set engines.local.lvm.enabled=false --create-namespace

helm ls -n openebs


cat<<EOF>>/tmp/lvm-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-lvmpv
parameters:
  storage: "lvm"
  volgroup: "lvmvg"
provisioner: local.csi.openebs.io

EOF
# You can use the LVM Storage Class for testing purpose, in this script used the loopback device for dynamic provisining. you can assign additional disk for this volume group for testing.
# kubectl apply -f /tmp/lvm-storage-class.yaml

rm -f /tmp/lvm-storage-class.yaml

kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
 
# Installing ISTIO
curl -L https://istio.io/downloadIstio | sh -

cp istio-1.*/bin/istioctl /usr/local/bin/

# Uncomment below to install Istio

istioctl completion bash > /etc/bash_completion.d/istioctl 

istioctl install --set profile=demo -y

kubectl create ns test-ns

kubectl label namespace test-ns istio-injection=enabled

# Add HashiCorp Vault using helm and enable UI for testing.
# helm repo add hashicorp https://helm.releases.hashicorp.com
# helm repo update
# helm install vault hashicorp/vault --set='ui.enabled=true' --set='ui.serviceType=LoadBalancer' --namespace vault --create-namespace


echo "Lab is ready to testing..."
