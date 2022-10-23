#!/bin/bash
# auth zzf.zhang

workdir=$(
  cd $(dirname $0)
  pwd
)

# consul / node_exporter etc.
_init_env() {
  localIp=$1
  while :; do
    cd ${workdir}
    echo "dirname: ${workdir}"
    read -p "Enter the NodeIp: " ip
    if [ "${ip}" == "" ]; then
      break
    fi
    read -p "Enter the port for ssh @${ip}[default 22]: " port
    port=${port:-22}
    read -p "Enter the username for ssh @${ip}[default admin]: " username
    username=${username:-admin}
    read -p "Enter the password for ssh @${ip}[default 0.]: " password
    password=${password:-0.}
    _init_env_func ${localIp} ${username} ${password} ${ip} ${port}
  done
}

_init_env_batch() {
  localIp=$1
  ipFile=${2}
  cat ${ipFile} | while read line; do
    echo "start int env-> ${line}"
    _init_env_func ${localIp} ${line}
  done
}

_init_env_func() {
  # localIp username password ip port
  localIp=${1}
  username=${2}
  password=${3}
  ip=${4}
  port=${5}

  # mount broker_cluster/broker
  ssh -n -p ${port} ${username}@${ip} "mkdir -p ~/broker_cluster/broker"
  # isntall nfs-common
  ssh -n -p ${port} ${username}@${ip} "echo ${password}|\
        sudo -S apt install nfs-common -y \
        "
  ssh -n -p ${port} ${username}@${ip} "echo ${password}|\
        sudo -S mount ${localIp}:/home/admin/broker_cluster/broker ~/broker_cluster/broker &>/dev/null"
  # start consul
  ssh -n -p ${port} ${username}@${ip} "mkdir -p ~/broker_cluster/consul 2>/dev/null;\
        pkill consul && sleep 8s; \
        cd ~/broker_cluster/consul && rm -rf data; \
        nohup ../broker/consul agent -bind=${ip} -data-dir=./data -retry-join=${localIp} &>./nohup.out & \
        "
  # start node-exporter
  ssh -n -p ${port} ${username}@${ip} "mkdir -p ~/broker_cluster/node_exporter 2>/dev/null ; \
        pkill -9 node_exporter && sleep 3s ; \
        cd ~/broker_cluster/node_exporter ; nohup ../broker/node_exporter &>./nohup.out & \
        "
  ssh -n -p ${port} ${username}@${ip} "curl -X PUT http://127.0.0.1:8500/v1/agent/service/register \
        -d '{\"Name\":\"node-exporter\", \"Address\":\"${ip}\", \"Port\":9100}' \
        "
  #
  echo "init env done-> ${ip}"
}

_init_vm() {
  while :; do
    cd ${workdir}
    echo "dirname: ${workdir}"
    read -p "Enter the NodeIp: " ip
    if [ "${ip}" == "" ]; then
      break
    fi
    read -p "Enter the port for ssh @${ip}[default 22]: " port
    port=${port:-22}
    read -p "Enter the username for ssh @${ip}[default admin]: " username
    username=${username:-admin}
    read -p "Enter the password for ssh @${ip}[default 0.]: " password
    password=${password:-0.}
    _init_vm_func ${username} ${password} ${ip} ${port}
  done
}

_init_vm_func() {
  # username password ip port
  username=${1}
  password=${2}
  ip=${3}
  port=${4}
  noReboot=${5}
  if [ "${username}" == "root" ]; then
    noReboot="noReboot"
  fi
  {
    expect <<EOF
spawn ssh-copy-id -p ${port} ${username}@${ip}
expect {
  "yes/no" { send "yes\n";exp_continue }
  "password" { send "${password}\n" }
}
expect eof
EOF
  } &
  #等待完成
  wait
  # scp bin to remote node
  scp -P ${port} vm_init.sh ${username}@${ip}:
  ssh -n -p ${port} ${username}@${ip} "echo ${password}|sudo -S bash ~/vm_init.sh ${username} ${noReboot}"
  echo "init_vm done-> ${ip}"
  return 0
}

_init_vm_batch() {
  # ipFile -> username password ip port
  ipFile=${1}
  cat ${ipFile} | while read line; do
    echo "start int vm-> ${line}"
    _init_vm_func ${line}
  done
}

case "$1" in
# ./cluster init_vm_batch ./ipFile.txt
# ipFile format: username password ip port
init_vm_batch)
  shift
  _init_vm_batch $@
  ;;
# ./cluster init_vm
init_vm)
  shift
  _init_vm $@
  ;;
# ./cluster init_env ${ipOfLocalHost}
init_env)
  shift
  _init_env $@
  ;;
# ./cluster init_env_batch ${ipOfLocalHost} ./ipFile.txt
init_env_batch)
  shift
  _init_env_batch $@
  ;;
source)
  # just for source by other script
  ;;
*)
  echo "Usage: ${0} init/start"
  ;;
esac
