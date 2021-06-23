#!/bin/bash

#list of interface and associate IPs
INTLIST=$(ip a |grep -i inet | awk '{print $7, $2}' | grep ^e)
echo "$INTLIST"

echo -n "Enter Interface name from above list eg. \"ens33\" :"
read INT

INT=${INT:-ens33}
IP=$(echo $INTLIST|grep $INT | awk '{print $2}'|cut -d "/" -f1)
echo "$INT and $IP"
sleep 3

HOST=$(hostname)
echo "Hang Tight. Pulling Required Images..."
kubeadm config images pull
echo "Required Images are pulled..."
if [ -f .cri_containerd ]
then
	# mentioning which CRI Socket to used
	kubeadm init --cri-socket /run/containerd/containerd.sock  --apiserver-advertise-address $IP --control-plane-endpoint $IP --node-name $HOST --v 7
else
	kubeadm init --apiserver-advertise-address $IP --control-plane-endpoint $IP --node-name $HOST --v 7
fi

sleep 5

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


kubeadm token create --print-join-command --ttl 0 2>/dev/null > 99-node-join.sh
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
chmod +x 99-node-join.sh
echo "alias ks=kubectl" >> ~/.bashrc
source ~/.bashrc
rm -f .cri_* 2>/dev/null
