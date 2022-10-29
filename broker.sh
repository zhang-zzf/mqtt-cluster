#!/bin/bash
# auth zzf.zhang

workdir=$(
  cd $(dirname $0)
  pwd
)

_buildVmOptions() {
  serverIp=${1}
  hugePage=${2}
  opt="-server "
  # heapSize
  read -p "Enter the heap size for broker @${serverIp}[default 32g]: " heapSize
  heapSize=${heapSize:-32g}
  opt="${opt} -Xms${heapSize} -Xmx${heapSize}"
  read -p "Enter the thread.num for broker @${serverIp}[32 for 4W TPS]: " threadNum
  threadNum=${threadNum:-32}
  opt="${opt} -Dmqtt.server.thread.num=${threadNum}"
  # jdk17
  opt="${opt} --add-opens java.base/java.nio=ALL-UNNAMED"
  # gc
  opt="${opt} -XX:+UseZGC \"-Xlog:safepoint,classhisto*=trace,age*,gc*=info:file=./gc-%p-%t.log:time,tid,tags:filecount=8,filesize=64m\""
  read -p "Enter the gc.ZAllocationSpikeTolerance[5]: " zast
  zast=${zast:-5}
  opt="${opt} -XX:ZAllocationSpikeTolerance=${zast}"
  read -p "Enter the gc.thread.num: " gcThreadNum
  if [ "${gcThreadNum}" != "" ]; then
    opt="${opt} -XX:ConcGCThreads=${gcThreadNum}"
  fi
  # zgc 主动 GC 时间间隔
  read -p "Enter the gc.interval.seconds: " gcInterval
  if [ "${gcInterval}" != "" ]; then
    opt="${opt} -XX:ZCollectionInterval=${gcInterval}"
  fi
  # JVM hugepage
  if [ "${hugePage}" != "" ]; then
    opt="${opt} -XX:+UseLargePages"
  fi
  # appName (most for metric usage)
  read -p "Enter the appName: " appName
  if [ "${appName}" != "" ]; then
    opt="${opt} -DappName=${appName}"
  fi
  # listened addresses
  read -p "Enter the listened addresses for broker @${serverIp}[default mqtt://${serverIp}:1883]: " listened
  listened=${listened:-mqtt://${serverIp}:1883}
  opt="${opt} -Dmqtt.server.listened=${listened}"
  # start spring context
  read -p "enable spring context[Y/n]: " spCtx
  spCtx=${spCtx:-y}
  if [ "${spCtx,}" == "y" ]; then
    opt="${opt} -Dspring.enable=true"
  fi
  # broker cluster config
  read -p "enable cluster mode[Y/n]: " cluster
  cluster=${cluster:-y}
  if [ "${cluster,}" == "y" ]; then
    opt="${opt} -Dmqtt.server.cluster.enable=true"
    # node name
    read -p "Enter the node name for broker @${serverIp}[default ${serverIp}]: " nodeName
    nodeName=${nodeName:-${serverIp}}
    opt="${opt} -Dmqtt.server.cluster.nodeName=${nodeName}"
    # join the cluster
    read -p "Enter the cluster that broker @${serverIp} to join[Format mqtt://ip:port]: " toJoin
    if [ "${toJoin}" != "" ]; then
      opt="${opt} -Dmqtt.server.cluster.join=${toJoin}"
    fi
    # node name
    read -p "Enter the channel.num[32 for 16C]: " channels
    channels=${channels:-32}
    opt="${opt} -Dmqtt.server.cluster.node.channel.num=${channels}"
  fi
  # prometheus jvm exporter
  opt="${opt} -Dprometheus.export.address=${serverIp}:0"
  # return the opt
  echo ${opt}
}

_start() {
  redisUrl=$1
  programArgs=$2
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
    read -p "Linux Huge Pages size[18G=9216,36G=[18432]]: " hugePageSize
    hugePageSize=${hugePageSize:-18432}
    # JVM 参数
    vmOptions="$(_buildVmOptions ${ip} ${hugePageSize})"
    # broker 依赖的 redis url
    vmOptions="${vmOptions} -Dmqtt.server.cluster.db.redis.url=${redisUrl}"
    echo "jvm options: ${vmOptions}"
    read -p "continue? [Y/n]: " jvmOk
    jvmOk=${jvmOk:-y}
    # 把变量中的第一个字符换成小写
    if [ "${jvmOk,}" != "y" ]; then
      echo "jvm options is not ok, please reenter it"
      continue
    fi
    echo "${password}" | ssh -tt -p ${port} ${username}@${ip} "sudo pkill java"
    if [ "${hugePageSize}" != "" ]; then
      echo "enable Linux Huge Pages: ${hugePageSize}"
      echo "${password}" | ssh -tt -p ${port} ${username}@${ip} \
        "sudo bash -c \"echo ${hugePageSize} > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages\""
      echo "Now check after change Linux Huge Pages "
      ssh -p ${port} ${username}@${ip} "cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
    fi
    ssh -p ${port} ${username}@${ip} "sleep 3s"
    # start the broker
    ssh -p ${port} ${username}@${ip} "cd ~/broker_cluster && \
            ulimit -n 10280000; nohup broker/jdk/default/bin/java ${vmOptions} \
            -jar broker/mqtt.jar ${programArgs} &>/dev/null &"
  done
}

# gatewayIp serverIp cluster
# mqtt://192.168.0.1:1883 192.168.1.1 1883 redis://10.255.1.41:7000
_start_test() {
  cd ${workdir}
  toJoin=${1}
  ip=${2}
  listened=${3}
  redisUrl=${4}
  mqttListened="mqtt://${ip}:${listened}"
  heapSize="16g"
  threadNum=16
  port=22
  # 修改 username 需慎重
  username="admin"
  password="0."
  # jvm_opt
  opt="-server "
  # heapSize
  opt="${opt} -Xms${heapSize} -Xmx${heapSize}"
  opt="${opt} -Dmqtt.server.thread.num=${threadNum}"
  # jdk17
  opt="${opt} --add-opens java.base/java.nio=ALL-UNNAMED"
  # gc
  opt="${opt} -XX:+UseZGC"
  opt="${opt} -Dmqtt.server.listened=${mqttListened}"
  # start spring context
  opt="${opt} -Dspring.enable=true"
  opt="${opt} -Dmqtt.server.cluster.enable=true"
  opt="${opt} -Dmqtt.server.cluster.nodeName=${mqttListened}"
  if [ "${toJoin}" != "mqtt" ]; then
    opt="${opt} -Dmqtt.server.cluster.join=${toJoin}"
  fi
  if [ "${redisUrl}" != "" ]; then
    opt="${opt} -Dmqtt.server.cluster.db.redis.url=${redisUrl}"
  fi
  opt="${opt} -Dmqtt.server.cluster.node.channel.num=${threadNum}"
  # prometheus jvm exporter
  opt="${opt} -Dprometheus.export.address=${ip}:0"
  echo "jvm_opt-> ${opt}"
  ssh -p ${port} ${username}@${ip} "\
    pkill -f mqtt.server.listened=${mqttListened} && sleep 3s && \
    ps -ef|grep mqtt.server.listened=${mqttListened}"
  # start the broker
  dir="~/broker_cluster/${listened}"
  ssh -p ${port} ${username}@${ip} "mkdir -p ${dir} &>/dev/null; \
   cd ${dir} && \
      nohup ~/broker_cluster/broker/jdk/default/bin/java ${opt} \
      -jar ~/broker_cluster/broker/mqtt.jar &>/dev/null &"
}

_end_test() {
  ip=${1}
  listened=${2}
  mqttListened="mqtt://${ip}:${listened}"
  port=22
  # 修改 username 需慎重
  username="admin"
  password="0."
  ssh -p ${port} ${username}@${ip} "\
    pkill -f mqtt.server.listened=${mqttListened} && sleep 3s && \
    ps -ef|grep mqtt.server.listened=${mqttListened}"

}

# gatewayIp serverIp cluster
# 192.168.0.1 192.168.1.1 redis://10.255.1.43
_init_start() {
  cd ${workdir}
  gatewayIp=${1}
  ip=${2}
  redisUrl=${3}
  heapSize=32g
  # 9G=4608,18G=9216,36G=[18432]
  hugePageSize=18432
  # for 32CPU
  threadNum=64
  port=22
  # 修改 username 需慎重
  username="root"
  password="Root0.0."
  source ./cluster.sh source
  _init_vm_func ${username} ${password} ${ip} ${port}
  _init_env_func ${gatewayIp} ${username} ${password} ${ip} ${port}
  # hugePage
  echo "enable Linux Huge Pages: ${hugePageSize}"
  echo "${password}" | ssh -tt -p ${port} ${username}@${ip} \
    "sudo bash -c \"echo ${hugePageSize} > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages\""
  echo "Now check after change Linux Huge Pages "
  ssh -p ${port} ${username}@${ip} "cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
  # jvm_opt
  opt="-server "
  # heapSize
  opt="${opt} -Xms${heapSize} -Xmx${heapSize}"
  opt="${opt} -Dmqtt.server.thread.num=${threadNum}"
  # jdk17
  opt="${opt} --add-opens java.base/java.nio=ALL-UNNAMED"
  # gc
  opt="${opt} -XX:+UseZGC \"-Xlog:safepoint,classhisto*=trace,age*,gc*=info:file=./gc-%p-%t.log:time,tid,tags:filecount=8,filesize=64m\""
  opt="${opt} -XX:ZAllocationSpikeTolerance=5"
  opt="${opt} -XX:+UseLargePages"
  opt="${opt} -Dmqtt.server.listened=mqtt://${ip}:1883"
  # start spring context
  opt="${opt} -Dspring.enable=true"
  opt="${opt} -Dmqtt.server.cluster.enable=true"
  opt="${opt} -Dmqtt.server.cluster.nodeName=${ip}"
  if [ "${toJoin}" != "" ]; then
    opt="${opt} -Dmqtt.server.cluster.join=${toJoin}"
  fi
  opt="${opt} -Dmqtt.server.cluster.node.channel.num=${threadNum}"
  # prometheus jvm exporter
  opt="${opt} -Dprometheus.export.address=${ip}:0"
  opt="${opt} -Dmqtt.server.cluster.db.redis.url=${redisUrl}"
  echo "jvm_opt-> ${opt}"
  # start the broker
  ssh -p ${port} ${username}@${ip} "cd ~/broker_cluster && \
      ulimit -n 10280000; nohup broker/jdk/default/bin/java ${opt} \
      -jar broker/mqtt.jar &>/dev/null &"
}

case "$1" in
start)
  # ./broker.sh start redis://10.255.1.42:7000 mainArgs
  shift
  _start $@
  echo "start done"
  ;;
init_start)
  # ./broker.sh start redis://10.255.1.42:7000 mainArgs
  shift
  _init_start $@
  echo "init_start done"
  ;;
start_test)
  # ./broker.sh start redis://10.255.1.42:7000 mainArgs
  shift
  _start_test $@
  echo "init_test done"
  ;;
end_test)
  # ./broker.sh start redis://10.255.1.42:7000 mainArgs
  shift
  _end_test $@
  echo "end_test done"
  ;;
*)
  echo "Usage: ${0} init/start"
  ;;
esac
