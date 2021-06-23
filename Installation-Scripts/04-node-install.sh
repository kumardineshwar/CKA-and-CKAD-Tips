#/bin/bash

echo -n "Enter worker node name : "
read NODE
echo -n "Enter CRI to install crio:docker:containerd - : "
read CRI
SCRIPT="01-$CRI-install.sh 02-kubeadm-install.sh 99-node-join.sh"
echo $CRI
read a
#NODE=$1
echo $SCRIPT
ssh $NODE "mkdir -p /tmp/k8s"
scp $SCRIPT $NODE:/tmp/k8s/

ssh $NODE chmod +x /tmp/k8s/*

ssh $NODE 'for i in $(ls  /tmp/k8s/*|sort -h); do echo "$i"; sh "$i"; done'

ssh $NODE rm -rf /tmp/k8s 2>/dev/null

sleep 5
kubectl label node $NODE node-role.kubernetes.io/worker=
kubectl get nodes -o wide

