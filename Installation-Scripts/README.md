# Cluster Installation Script

# Pre-Req 
---
 1. Setup 2 Unubtu-20.x vm nodes
 2. setup Static IP to both nodes
 3. update /etc/hosts file for all nodes (for Virutal box make sure its your host-only-interface IPs)
    
     - eg. 
      192.168.0.10 master-1
      192.168.0.11 worker-1
      192.168.0.12 worker-2
      
  4. Create ssh-keys and setup password-less access 
     
     - ssh-keygen -t rsa -b 4096 -N '' 
     
     - ssh-copy-id "node-name" 
  
  5. Clone the Script on your master-node
  
     - git clone https://github.com/kumardineshwar/CKA-and-CKAD-Tips.git
     - cd Installation-Scripts
  7. Set the executable permission to shell scripts
    
    - chmod +x *.sh
  
  8. run the "01-docker-install.sh" to install docker container run-time, you can skip if CRI is already installed
    
    - sh ./01-docker-install.sh # Use it to install Docker
    - sh ./01-crio-install.sh # use it to install CRIO 
  
  9. run the "02-kubeadm-install.sh" to install latest kubernetes binaries. 
   
    - sh ./02-kubeadm-install.sh
    
  10. execute the "03-cluster-install.sh" to setup first master nodes (The script will also add weave CNI to cluster).
  
    - sh ./03-cluster-install.sh
   
  11. Finally run "04-node-install.sh" script to add worker nodes
  
    - sh ./04-node-install.sh
    
    - it will ask for the worker node name eg. "worker-1"
  
  12. Run "05-install-nfs-server.sh" to setup nfs server on master node
  
    - sh ./05-install-nfs-server.sh

    - it will create /mnt/nfs_share on master node

  13. To Remove node run "100-node-remove.sh" script to add worker nodes
  
    - sh ./100-node-remove.sh
    
    - it will ask for the worker node name eg. "worker-1"
  ---
