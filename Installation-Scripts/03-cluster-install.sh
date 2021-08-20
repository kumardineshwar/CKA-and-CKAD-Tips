#!/bin/bash

HOST=$(hostname)
IPLIST=$(ip -o addr show up primary scope global | awk '{print $4}' |cut -d"/" -f1)
echo -e "$IPLIST"
read -p "Enter Ip Address from above list eg. : " IP
IP=${IP:-127.0.0.1}
if [ "$IP" == "127.0.0.1" ]
then

	IP=$(echo -e "$IPLIST" | head -n 1)
	echo "No IP Provided, using first public Interface IP : $IP"

fi	

echo "Cluster will running on $IP : $HOST"

sleep 2
if [ $(grep -c $IP /etc/hosts) -lt 1 ]
then
	echo "Missing /etc/hosts entry, adding below entry to /etc/hosts for Cluster Installation"
	cp -f /etc/hosts /etc/hosts.orig
	echo "$IP $HOST" |tee -a /etc/hosts
fi
read -p "Enter the CNI to use weave|calico :" CNI
CNI=${CNI:-weave}

echo "Hang Tight. Pulling Required Images..."

kubeadm config images pull
echo "Required Images are pulled..."
if [ -f .cri_containerd ]
then
	# mentioning which CRI Socket to used
	kubeadm init --cri-socket /run/containerd/containerd.sock  --apiserver-advertise-address $IP --control-plane-endpoint $IP --pod-network-cidr 192.168.0.0/16 --node-name $HOST --v 7
else
	kubeadm init --apiserver-advertise-address $IP --control-plane-endpoint $IP --pod-network-cidr 192.168.0.0/16 --node-name $HOST --v 7
fi

sleep 5

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


kubeadm token create --print-join-command --ttl 0 2>/dev/null > 99-node-join.sh

if [ "$CNI" == "calico" ]
then
	echo "Installing Calico CNI with default POD CIDR 192.168.0.0/16"
	curl https://docs.projectcalico.org/manifests/calico.yaml  | kubectl apply -f -
	curl -o /usr/local/bin/calicoctl -O -L  "https://github.com/projectcalico/calicoctl/releases/download/v3.19.1/calicoctl" 
	curl -o /usr/local/bin/kubectl-calico -O -L  "https://github.com/projectcalico/calicoctl/releases/download/v3.19.1/calicoctl"
	chmod +x  /usr/local/bin/calicoctl  /usr/local/bin/kubectl-calico
else
	echo "Installing Weave as Default CNI"
	kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
fi

chmod +x 99-node-join.sh
if [ "$SHELL" == "/usr/bin/zsh" ]
then
	echo '[[ $commands[kubectl] ]] && source <(kubectl completion zsh)' >> ~/.zshrc
	echo "alias ks=kubectl" >> ~/.zshrc
        echo "complete -F __start_kubectl ks"  >> ~/.zshrc
	source ~/.zshrc 
else
	echo "Setting up bash completion"
	echo "source <(kubectl completion bash)" >> ~/.bashrc
	echo "alias ks=kubectl" >> ~/.bashrc
        echo "complete -F __start_kubectl ks"  >> ~/.bashrc
	source ~/.bashrc
fi


rm -f .cri_* 2>/dev/null
