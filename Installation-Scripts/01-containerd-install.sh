#!/bin/bash

# use this script to install crio 
#  Refrence - https://kubernetes.io/docs/setup/production-environment/container-runtimes/
/usr/sbin/swapoff -a
rm -f .cri_* 2>/dev/null
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
rm -f /etc/apt/sources.list.d/*cri-o* 2>/dev/null >/dev/null
rm -rf /etc/crio >/dev/null 2>/dev/null
sudo apt-get update
sudo apt-get install containerd -y

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
#sed -i '/containerd.runtimes.runc.options/a SystemdCgroup = true' /etc/containerd/config.toml
sed -i 's/SystemdCgroup =.*/SystemdCgroup = true/g' /etc/containerd/config.toml




#cat <<EOF | sudo tee /etc/crio/crio.conf.d/02-cgroup-manager.conf
#[crio.runtime]
#conmon_cgroup = "pod"
##cgroup_manager = "cgroupfs"
#cgroup_manager = "systemd"
#EOF

sudo systemctl daemon-reload
sudo systemctl restart containerd
touch .cri_containerd
