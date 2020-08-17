#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# *********************************************************************/

CLDINITPATH='/var/lib/cloud/scripts/per-instance'
AGENT_PATH='/usr/local/aegis'

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}

providerck()
{
    if [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then 
        PROVIDER='aws'
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'      
    elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
        PROVIDER='do'
    elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
        PROVIDER='ali'
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        PROVIDER='azure'
    else
        PROVIDER='undefined'  
    fi
}
providerck

check_root(){
    if [ $(id -u) -ne 0 ]; then
        echoR "Please run this script as root user or use sudo"
        exit 1
    fi
}

set_ssh_alive(){
    if [ "${PROVIDER}" = 'azure' ]; then
        sed -i '/ClientAliveInterval/d' /etc/ssh/sshd_config
        echo 'ClientAliveInterval 235' >> /etc/ssh/sshd_config
    fi
}


stop_aegis(){
    killall -9 aegis_cli aegis_update aegis_cli aegis_quartz >/dev/null 2>&1
    killall -9 AliYunDun AliHids AliYunDunUpdate >/dev/null 2>&1
    if [ -f "/etc/init.d/aegis" ]; then
        /etc/init.d/aegis stop  >/dev/null 2>&1
    fi    
    printf "%-40s %40s\n" "Stopping aegis" "[  OK  ]"
}

remove_aegis(){
    if [ -d ${AGENT_PATH} ];then
        rm -rf ${AGENT_PATH}/aegis_client
        rm -rf ${AGENT_PATH}/aegis_update
        rm -rf ${AGENT_PATH}/alihids
        rm -rf ${AGENT_PATH}/aegis_quartz
        rm -f /etc/init.d/aegis
    fi  
}

uninstall_aegis(){
    if [ "${PROVIDER}" = 'ali' ]; then 
        stop_aegis
        remove_aegis
    fi
}

install_cloudinit(){
    if [ ! -d ${CLDINITPATH} ]; then
        mkdir -p ${CLDINITPATH}
    fi    
    which cloud-init >/dev/null 2>&1
    if [ ${?} = 1 ]; then
        if [ ${OSNAME} = 'ubuntu' ]; then
            apt-get install cloud-init -y >/dev/null 2>&1
        else
            if [ "${PROVIDER}" = 'ali' ]; then
                yum -y install python-pip > /dev/null 2>&1
                test -d /etc/cloud && mv /etc/cloud /etc/cloud-old; cd /tmp/
                wget -q http://ecs-image-utils.oss-cn-hangzhou.aliyuncs.com/cloudinit/ali-cloud-init-latest.tgz
                tar -zxvf ali-cloud-init-latest.tgz > /dev/null 2>&1
                OS_VER=$(cat /etc/redhat-release | awk '{printf $4}'| awk -F'.' '{printf $1}')
                bash /tmp/cloud-init-*/tools/deploy.sh centos ${OS_VER}
                rm -rf ali-cloud-init-latest.tgz cloud-init-*
            else
                yum install cloud-init -y >/dev/null 2>&1
            fi    
        fi    
    fi    
}

setup_cloud(){
    cat > ${CLDINITPATH}/per-instance.sh <<END 
#!/bin/bash
MAIN_URL='https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Cloud-init/per-instance.sh'
BACK_URL='https://cloud.litespeed.sh/Cloud-init/per-instance.sh'
STATUS_CODE=\$(curl --write-out %{http_code} -sk --output /dev/null \${MAIN_URL})
[[ "\${STATUS_CODE}" = 200 ]] && /bin/bash <( curl -sk \${MAIN_URL} ) || /bin/bash <( curl -sk \${BACK_URL} )
END
    chmod 755 ${CLDINITPATH}/per-instance.sh
}

cleanup (){
    if [ -d /usr/local/CyberCP ]; then
        if [ "${OSNAME}" != 'centos' ]; then
            sudo apt-get remove firewalld -y > /dev/null 2>&1
        fi    
    fi
    if [ "${OSNAME}" = 'ubuntu' ]; then
        sudo apt-get remove unattended-upgrades -y > /dev/null 2>&1
    fi
    # Legal
    if [ -f /etc/legal ]; then
        mv /etc/legal /etc/legal.bk
    fi
    #cloud-init here
    rm -f /var/log/cloud-init.log
    rm -f /var/log/cloud-init-output.log
    rm -rf /var/lib/cloud/data
    rm -rf /var/lib/cloud/instance
    rm -rf /var/lib/cloud/instances/*
    #system log
    rm -rf /var/log/unattended-upgrades
    rm -f /var/log/apt/history.log*
    rm -f /var/log/apt/term.log*
    rm -f /var/log/apt/eipp.log*
    rm -f /var/log/auth.log*
    rm -f /var/log/dpkg.log*
    rm -f /var/log/kern.log*
    rm -f /var/log/ufw.log*
    rm -f /var/log/alternatives.log
    rm -f /var/log/apport.log
    rm -rf /var/log/journal/*
    rm -f /var/log/syslog*
    rm -f /var/log/btmp*
    rm -f /var/log/wtmp*
    rm -f /var/log/yum.log*
    rm -f /var/log/secure
    rm -f /var/log/messages
    rm -f /var/log/dmesg
    rm -f /var/log/audit/audit.log
    rm -f /var/log/maillog
    rm -f /var/tuned/tuned.log
    rm -f /var/log/fontconfig.log
    #aws
    rm -f /var/log/amazon/ssm/*
    #azure
    rm -f /var/log/azure/*
    rm -f /var/log/waagent.log
    #ali
    rm -f /var/log/ecs_network_optimization.log
    #component log
    rm -f /usr/local/lscp/logs/*
    rm -f /var/log/mail.log*
    rm -f /var/log/mail.err
    rm -f /var/log/letsencrypt/letsencrypt.log*
    rm -f /var/log/fail2ban.log* 
    rm -f /var/log/mysql/error.log
    #rm -f /etc/mysql/debian.cnf
    rm -f /var/log/redis/redis-server.log
    rm -rf /usr/local/lsws/logs/*
    rm -f /root/.mysql_history
    rm -f /var/log/php*.log
    rm -f /var/log/installLogs.txt
    #Cyberpanel
    rm -f /var/log/anaconda/*
    rm -f /usr/local/lscp/logs/*
    rm -f /usr/local/lscp/cyberpanel/logs/*
    rm -rf  /usr/local/CyberCP/.idea/*
    #key
    rm -f /root/.ssh/authorized_keys
    rm -f /root/.ssh/cyberpanel*
    #password
    rm -f /root/.litespeed_password
    rm -f /root/.bash_history
    if [ "${PROVIDER}" = 'aws' ]; then
        sudo passwd -d root >/dev/null 2>&1
        sudo sed -i 's/root::/root:*:/g' /etc/shadow >/dev/null 2>&1
        if [ -d /home/ubuntu ]; then
            rm -f /home/ubuntu/.mysql_history
            rm -f /home/ubuntu/.bash_history
            rm -f /home/ubuntu/.ssh/authorized_keys   
            rm -f /home/ubuntu/.litespeed_password
        fi    
    fi  
    if [ "${PROVIDER}" = 'google' ] || [ "${PROVIDER}" = 'azure' ]; then
        sudo passwd -d root >/dev/null 2>&1
        sudo sed -i 's/root::/root:*:/g' /etc/shadow >/dev/null 2>&1
        ALL_HMFD=$(ls /home/)
        for i in ${ALL_HMFD[@]}; do
            if [ "${i}" != 'ubuntu' ] && [ "${i}" != 'cyberpanel' ] && [ "${i}" != 'vmail' ] && [ "${i}" != 'docker' ]; then
                rm -rf "/home/${i}"
            fi
        done  
    fi
}

main_claunch(){
    check_os
    check_root
    #uninstall_aegis
    set_ssh_alive
    install_cloudinit
    setup_cloud
    cleanup
}
main_claunch
exit 0