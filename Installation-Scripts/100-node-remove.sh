#!/bin/bash

# Use this script to remove nodes including master and worker nodes


echo -n "Enter Node name to remove :"
read node

# disabling nodes 
kubectl cordon $node

kubectl delete node $node

ssh $node "kubeadm reset --force"
