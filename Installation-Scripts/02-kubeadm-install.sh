#!/bin/bash

VER="1.20.7-00"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

sudo modprobe br_netfilter
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
sleep 5
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-cache madison kubeadm |head -n 20 | tr -d " "| awk -F "|" '{print $2}' > /tmp/k8s-version-to-install
if [ "$VER" == "FIXME" ]
then
cat  /tmp/k8s-version-to-install
   read -p "Enter the kubernetes version to install the default will $VER  : " K8S
   K8S=${K8S:-"1.20.7-00"}
   if [ "$VER" != "$K8S" ]
     then
     sed -i "s/^VER=.*/VER=\"$K8S\"/g" ./02-kubeadm-install.sh
     VERI=$K8S
  else
     VERI=$VER
  fi
else

     VERI=$VER

fi
echo -e "Going to install : $VERI "

/usr/sbin/swapoff -a
sudo apt-get update
#sudo apt-cache madison kubeadm
sudo apt-get install -y kubelet=$VERI kubeadm=$VERI kubectl=$VERI
sudo apt-mark hold kubelet kubeadm kubectl
echo "alias ks=kubectl" >> ~/.bashrc
source ~/.bashrc
#installing nfs client on all nodes
sudo apt install nfs-common -y
rm -f  /tmp/k8s-version-to-install 2>/dev/null
