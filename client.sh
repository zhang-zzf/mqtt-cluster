#!/usr/bin/env bash

workdir=$(cd $(dirname $0); pwd)

# 主机存在
# 判断是否存在 JAVA 进程
# 不存在
#  # 初始化 VM
#  # 初始化 ENV
#  # 启动 Java
# 存在

_startJvm() {
  # 启动 java 进程
  vmoptions=" -server \
              -xmx384m \
              -dmqtt.client.mode=true \
              -dprometheus.export.address=${ip}:0 \
              -dmqtt.client.thread.num=8  -dclient.startup.sleep=0"
  programargs="${serveraddress} ${ip}:0 64000 32 0 0 4000"
  ssh -p ${port} ${username}@${ip} "cd ~/broker_cluster && \
      nohup broker/jdk/default/bin/java ${vmoptions} \
      -jar broker/mqtt.jar ${programargs} &>/dev/null &"
}

source ./cluster.sh source
# 192.168.0.1 192.168.0.10 192.168.1.0 160 force
# 192.168.1.0
gatewayIp=${1}
serverAddress=${2}
subweb=${3}
force=${4}
usename="root"
password="password"
sshPort=22
# aliyun 每个交换机网段的第1个和最后3个IP地址为系统保留地址。
# 以192.168.1.0/24为例，192.168.1.0、192.168.1.253、192.168.1.254和192.168.1.255这些地址是系统保留地址
for ((i = 1; i < 253; i++)); do
  ip="$((${subweb} + ${i}))"
  ping ${ip} -c 1 -W 1 -n -4 -q &>/dev/null
  echo "ping ${ip} resp: $?"
  if [ $? == 0 ]; then
    # 主机存在
    # 判断 Java 进程是否存在
    processCnt=$(ssh -p ${port} ${username}@${ip} "ps -ef|grep java|wc -l")
    if [ ${processCnt} -lt 3 ]; then
      # 不存在
      _init_vm_func ${username} ${password} ${ip} ${sshPort}
      _init_env_func ${gatewayIp} ${username} ${password} ${ip} ${sshPort}
      _startJvm
    elif [ "${force}" == "force" ]; then
      # kill java 进程
      ssh -p ${port} ${username}@${ip} "echo ${password}|sudo -S pkill java && sleep 10s"
      # 启动 java 进程
      _startJvm
    fi
  fi
done
