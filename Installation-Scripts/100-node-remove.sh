#!/bin/bash

# Use this script to remove nodes including master and worker nodes


echo -e "\t\tNode List"
echo "======================= Node List ============================="
kubectl get nodes

echo "==============================================================="
if [ "$1" != "" ]
then
	node="$1"
else
echo -n "Enter Node name to remove :"
read node
fi
echo "removing node $node"
echo -n "Press Enter to Continue"
read a
# disabling nodes 
kubectl cordon $node

kubectl delete node $node

ssh $node "systemctl stop kubelet docker && kubeadm reset --force && reboot"
