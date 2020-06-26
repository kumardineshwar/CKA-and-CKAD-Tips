#!/bin/bash

IP=$(ifconfig ens33 | grep inet |head -1 | tr -s " " |cut -d " " -f3)
HOST=$(hostname)

kubeadm init --apiserver-advertise-address $IP --control-plane-endpoint $IP --node-name $HOST

sleep 5

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config


kubeadm token create --print-join-command --ttl 0 2>/dev/null > 99-node-join.sh
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
chmod +x 99-node-join.sh

echo "alias ks=kubectl" >> .bashrc
source .bashrc


