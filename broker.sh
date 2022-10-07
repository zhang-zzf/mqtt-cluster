#!/bin/bash
# auth zzf.zhang

workdir=$(cd $(dirname $0); pwd)

_buildVmOptions() {
    serverIp=${1}
    opt="-server "
    # heapSize
    read -p "Enter the heap size for broker @${serverIp}[default 16g]: " heapSize
    heapSize=${heapSize:-16g}
    opt="${opt} -Xmx${heapSize}"
    read -p "Enter the thread.num for broker @${serverIp}[128]: " threadNum
    threadNum=${threadNum:-128}
    opt="${opt} -Dmqtt.server.thread.num=${threadNum}"
    # jdk17
    opt="${opt} --add-opens java.base/java.nio=ALL-UNNAMED"
    # gc
    opt="${opt} -XX:+UseZGC \"-Xlog:safepoint,classhisto*=trace,age*,gc*=info:file=./gc-%p-%t.log:time,tid,tags:filecount=8,filesize=64m\""
    # broker cluster config
    opt="${opt} -Dspring.enable=true -Dmqtt.server.cluster.enable=true"
    # node name
    read -p "Enter the node name for broker @${serverIp}[default ${serverIp}]: " nodeName
    nodeName=${nodeName:-${serverIp}}
    opt="${opt} -Dmqtt.server.cluster.nodeName=${nodeName}"
    read -p "Enter the listened addresses for broker @${serverIp}[default mqtt://${serverIp}:1883]: " listened
    listened=${listened:-mqtt://${serverIp}:1883}
    opt="${opt} -Dmqtt.server.listened=${listened}"
    # join the cluster
    read -p "Enter the cluster that broker @${serverIp} to join[Format mqtt://ip:port]: " toJoin
    if [ "${toJoin}" != "" ]; then
        opt="${opt} -Dmqtt.server.cluster.join=${toJoin}"
    fi
    # prometheus jvm exporter
    opt="${opt} -Dprometheus.export.address=${serverIp}:0"
    # return the opt
    echo ${opt}
}

_start() {
    redisUrl=$1
    programArgs=$2
    while :;do
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
        # JVM 参数
        vmOptiions="$(_buildVmOptions ${ip})"
        # broker 依赖的 redis url
        vmOptiions="${vmOptiions} -Dmqtt.server.cluster.db.redis.url=${redisUrl}"
        echo "jvm options: ${vmOptiions}"
        read -p "continue? yes/[no]: " jvmOk
        if [ "${jvmOk}" != "yes" ]; then
            echo "jvm options is not ok, please reenter it"
            continue
        fi
        echo "${password}"|ssh -tt -p ${port} ${username}@${ip} "sudo pkill java"
        ssh -p ${port} ${username}@${ip} "sleep 3s"
        # start the broker
        ssh -p ${port} ${username}@${ip} "cd ~/broker_cluster && \
            nohup broker/jdk/default/bin/java ${vmOptiions} \
            -jar broker/mqtt.jar ${programArgs} &>/dev/null &"
    done
}

case "$1" in
start)
    # ./broker.sh start redis://10.255.1.42:7000 mainArgs
    shift;_start $@
    echo "start done"
;;
*)
    echo "Usage: ${0} init/start"
;;
esac
