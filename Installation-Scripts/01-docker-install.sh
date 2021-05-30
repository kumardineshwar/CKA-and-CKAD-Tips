#!/bin/bash

# (Install Docker CE)
## Set up the repository:
### Install packages to allow apt to use a repository over HTTPS
 systemctl stop crio  2>/dev/null
apt remove  cri-o cri-o-runc  -y
/usr/sbin/swapoff -a
sudo apt-get update && sudo apt-get install -y \
  apt-transport-https ca-certificates curl software-properties-common gnupg2
# Add Docker’s official GPG key:
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
# Add the Docker apt repository:
sudo add-apt-repository  "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
# Install Docker CE
sudo apt-get update && sudo apt-get install -y \
  containerd.io \
  docker-ce \
  docker-ce-cli
# Set up the Docker daemon
sudo touch  /etc/docker/daemon.json
sudo cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
sudo mkdir -p /etc/systemd/system/docker.service.d
# Restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker
