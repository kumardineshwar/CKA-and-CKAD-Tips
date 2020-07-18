#!/bin/bash
#Installing nfs-server, run on master-node
sudo apt install nfs-kernel-server -y
sudo mkdir -p /mnt/nfs_share
sudo chown -R nobody:nogroup /mnt/nfs_share/
sudo chmod 777 /mnt/nfs_share/
NET=$(ip a |grep -i inet | awk '{print $7, $2}' | grep ^e | awk '{print $2}' |cut -d"." -f1,2,3)

echo "/mnt/nfs_share  $NET.0/24(rw,sync,no_subtree_check)" >> /etc/exports

sudo systemctl restart nfs-kernel-server

