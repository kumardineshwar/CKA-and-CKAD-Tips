#/bin/bash

echo -n "Enter worker node name : "
read NODE
echo -n "Enter CRI to install crio:docker - : "
read CRI
SCRIPT="01-$CRI-install.sh 02-kubeadm-install.sh 99-node-join.sh"

#NODE=$1

scp $SCRIPT $NODE:~/

ssh $NODE chmod +x $SCRIPT

ssh $NODE 'SCRIPT="01-$CRI-install.sh 02-kubeadm-install.sh 99-node-join.sh";for i in $SCRIPT; do echo "$i"; sh "$i"; done'

ssh $NODE rm -f $SCRIPT

sleep 5

kubectl get nodes -o wide

