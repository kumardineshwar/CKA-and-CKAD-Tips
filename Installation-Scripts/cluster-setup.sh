#!/bin/bash
#

rm -f /tmp/setup_containerd.sh /tmp/setup_k8s.sh /tmp/node-join.sh /tmp/metallb-address-pool.yaml

cat<<EOF>> /tmp/setup_containerd.sh
#!/bin/bash

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
modprobe br_netfilter
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system
sysctl net.ipv4.ip_forward

apt-get install containerd -y

mkdir -p /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo sed -i 's/pause:3.8/pause:3.9/g' /etc/containerd/config.toml

sudo systemctl daemon-reload
systemctl restart containerd.service

sudo apt-get install kubeadm kubelet kubernetes-cni -y

sleep 10

EOF


for i in worker01 worker02 worker03; do scp /tmp/setup_containerd.sh $i:/tmp/setup_containerd.sh; done

for i in worker01 worker02 worker03 master01; do ssh $i "sh /tmp/setup_containerd.sh"; done

cat<<EOF>> /tmp/setup_k8s.sh
#!/bin/bash

IP=\$(ip a show ens33 | grep "192.168" | cut -d " " -f6 | cut -d"/" -f1)
HOST=\$(hostname)

kubeadm config images pull 

apt-get install kubectl -y

kubeadm init --cri-socket /run/containerd/containerd.sock --apiserver-advertise-address \$IP --control-plane-endpoint \$IP --pod-network-cidr 192.168.0.0/16 --node-name \$HOST --v=7

wget https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml -O /tmp/calico.yaml

export KUBECONFIG=/etc/kubernetes/admin.conf

kubeadm token create --print-join-command --ttl 0 2>/dev/null | tee /tmp/node-join.sh

mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
echo 'source <(kubectl completion bash)' >> /root/.bashrc


while [ \$(kubectl get nodes --no-headers | grep -c master01) -ne 1 ]; do sleep 10; done

sleep 30

kubectl apply -f /tmp/calico.yaml

EOF

bash /tmp/setup_k8s.sh

sleep 10 

for i in worker01 worker02 worker03; do scp /tmp/node-join.sh $i:/tmp/node-join.sh; done

for i in worker01 worker02 worker03; do ssh $i "sh /tmp/node-join.sh"; done

for i in worker01 worker02 worker03; do ssh $i "rm -f /tmp/setup_containerd.sh /tmp/node-join.sh"; done

# Clean UP

cp /tmp/node-join.sh node-join.sh

sleep 30

kubectl get nodes -o wide

wget https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml -O /tmp/metallb-native.yaml

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
sleep 30

kubectl apply -f /tmp/metallb-address-pool.yaml

for NODE in worker01 worker02 worker03 
do
kubectl label node $NODE node-role.kubernetes.io/worker=
done

rm -f /tmp/setup_containerd.sh /tmp/setup_k8s.sh /tmp/node-join.sh /tmp/metallb-address-pool.yaml
