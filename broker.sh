#!/bin/bash
# auth zzf.zhang

workdir=$(cd $(dirname $0); pwd)

_buildVmOptions() {
    serverIp=${1}
    hugePage=${2}
    opt="-server "
    # heapSize
    read -p "Enter the heap size for broker @${serverIp}[default 32g]: " heapSize
    heapSize=${heapSize:-32g}
    opt="${opt} -Xms${heapSize} -Xmx${heapSize}"
    read -p "Enter the thread.num for broker @${serverIp}[64]: " threadNum
    threadNum=${threadNum:-64}
    opt="${opt} -Dmqtt.server.thread.num=${threadNum}"
    # jdk17
    opt="${opt} --add-opens java.base/java.nio=ALL-UNNAMED"
    # gc
    opt="${opt} -XX:+UseZGC \"-Xlog:safepoint,classhisto*=trace,age*,gc*=info:file=./gc-%p-%t.log:time,tid,tags:filecount=8,filesize=64m\""
    read -p "Enter the gc.ZAllocationSpikeTolerance: " zast
    if [ "${zast}" != "" ]; then
        opt="${opt} -XX:ZAllocationSpikeTolerance=${zast}"
    fi
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
        read -p "Linux Huge Pages size[18G=9216,36G=[18432]]: " hugePageSize
        hugePageSize=${hugePageSize:-18432}
        # JVM 参数
        vmOptiions="$(_buildVmOptions ${ip} ${hugePageSize})"
        # broker 依赖的 redis url
        vmOptiions="${vmOptiions} -Dmqtt.server.cluster.db.redis.url=${redisUrl}"
        echo "jvm options: ${vmOptiions}"
        read -p "continue? [Y/n]: " jvmOk
        jvmOk=${jvmOk:-y}
        # 把变量中的第一个字符换成小写
        if [ "${jvmOk,}" != "y" ]; then
            echo "jvm options is not ok, please reenter it"
            continue
        fi
        echo "${password}"|ssh -tt -p ${port} ${username}@${ip} "sudo pkill java"
        if [ "${hugePageSize}" != "" ]; then
            echo "enable Linux Huge Pages: ${hugePageSize}"
            echo "${password}"|ssh -tt -p ${port} ${username}@${ip} \
                "sudo bash -c \"echo ${hugePageSize} > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages\""
            echo "Now check after change Linux Huge Pages "
            ssh -p ${port} ${username}@${ip} "cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
        fi
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
