#!/bin/bash

apt install nfs-common -y
username=${1}
max_files=10280000
if [ $(grep -c "fs.nr_open=${max_files}" /etc/sysctl.conf) -eq 0 ];then
    echo "\n# 进程级别最大文件数量\nfs.nr_open=${max_files}" >> /etc/sysctl.conf
    echo "\n# 进程级别最大文件数量\nfs.nr_open=${max_files} \n>> /etc/sysctl.conf"
fi
if [ $(grep -c "net.ipv4.ip_local_port_range = 1025 65535" /etc/sysctl.conf) -eq 0 ];then
    sh -c 'echo "\n# 修改端口可用范围\nnet.ipv4.ip_local_port_range = 1025 65535" >> /etc/sysctl.conf'
    echo "\n# 修改端口可用范围\nnet.ipv4.ip_local_port_range = 1025 65535 \n>> /etc/sysctl.conf"
fi
if [ $(grep -c "vm.max_map_count = 327680" /etc/sysctl.conf) -eq 0 ];then
    echo "\n# 进程级别 max_map_count 32W\nvm.max_map_count = 327680" >> /etc/sysctl.conf
    echo "\n# 进程级别 max_map_count 32W\nvm.max_map_count = 327680 \n>> /etc/sysctl.conf"
fi

if [ $(grep -c "${username}           soft    nofile          ${max_files}" /etc/security/limits.conf) -eq 0 ];then
    echo "\n${username}           soft    nofile          ${max_files}\
        \n${username}           hard    nofile          ${max_files}" \
        >> /etc/security/limits.conf
    echo "\n${username}           soft    nofile          ${max_files}\
          \n${username}           hard    nofile          ${max_files}\
          \n>> /etc/security/limits.conf"
fi

if [ $(grep -c "# /swap.img" /etc/fstab) -eq 0 ];then
     sed -i "s?/swap.img?# /swap.img?" /etc/fstab
fi

reboot
