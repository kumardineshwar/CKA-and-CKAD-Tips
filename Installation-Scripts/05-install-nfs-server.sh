#!/bin/bash
#Installing nfs-server, run on master-node
sudo apt install nfs-kernel-server -y
sudo mkdir -p /mnt/nfs_share
sudo chown -R nobody:nogroup /mnt/nfs_share/
sudo chmod 777 /mnt/nfs_share/

echo '/mnt/nfs_share  192.168.0.0/24(rw,sync,no_subtree_check)' >> /etc/exports

sudo systemctl restart nfs-kernel-server

