#!/usr/bin/env bash

workdir=$(
  cd $(dirname $0)
  pwd
)
echo "wordir-> $workdir"

# install docker
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get install expect ca-certificates curl gnupg lsb-release -y
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
sudo docker run hello-world

# nfs-server
# use root
sudo apt install nfs-kernel-server -y
sudo systemctl start nfs-kernel-server.service
mkdir "${workdir}/broker"
if [ $(grep -c "${workdir}/broker" /etc/exports) -eq 0 ]; then
  echo "${workdir}/broker *(ro,sync,subtree_check,no_root_squash)" | sudo tee -a /etc/exports
fi
sudo exportfs -a

cd ${workdir}
git clone https://github.com/zhang-zzf/middle-dotfiles

# docker-prometheus
git clone https://github.com/zhang-zzf/docker-prometheus
cd docker-prometheus
docker compose up -d
