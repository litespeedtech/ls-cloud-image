#!/bin/bash
# /********************************************************************
# LiteSpeed CyberPanel setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2021
# @Version: 1.0.2
# *********************************************************************/

NOWPATH=$(pwd)

echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}
echoR()
{
    echo -e "\033[38;5;203m${1}\033[39m"
}

providerck()
{
    if [ -e /sys/devices/virtual/dmi/id/product_uuid ] && [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then 
        PROVIDER='aws'
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'      
    elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
        PROVIDER='do'
    elif [ "$(dmidecode -s bios-vendor)" = 'Vultr' ];then
        PROVIDER='vultr'             
    elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
        PROVIDER='aliyun'
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        PROVIDER='azure'
    elif [ -e /etc/oracle-cloud-agent/ ]; then
        PROVIDER='oracle'        
    else
        PROVIDER='undefined'  
    fi
}

check_os()
{
    if [ -f /etc/redhat-release ] ; then
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
        OSNAME=centos
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}

upgrade() {
    echoG 'Updating system'
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
        apt-get update > /dev/null 2>&1
        echo -ne '#####                     (33%)\r'
        DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade > /dev/null 2>&1
        echo -ne '#############             (66%)\r'
        DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade > /dev/null 2>&1
        echo -ne '####################      (99%)\r'
        apt-get clean > /dev/null 2>&1
        apt-get autoclean > /dev/null 2>&1
        echo -ne '#######################   (100%)\r'
    else
        echo -ne '#                         (5%)\r'
        yum update -y > /dev/null 2>&1
        echo -ne '#######################   (100%)\r'
    fi  
    echoG 'Finish Update'  
}

install_basic_pkg(){
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install wget > /dev/null 2>&1
    else  
        apt-get -y install wget > /dev/null 2>&1
    fi
}

install_cyberpanel(){
    echoG 'Installing CyberPanel'
    ### The 1 1 will auto answer the prompt to install CyberPanel and OpenLiteSpeed
    ### and then accept the default values for the rest of the questions.     
    cd /opt/; wget -q https://cyberpanel.net/install.sh
    chmod +x install.sh
    printf "%s\n" 1 1 | bash install.sh
    echoG 'Finish CyberPanel'
    rm -rf cyberpanel cyberpanel.sh install.sh requirements.txt
}   

rm_agpl_pkg(){
    local RAINLOOP_PATH='/usr/local/CyberCP/public/rainloop'
    if [ -e ${RAINLOOP_PATH} ]; then
        rm -rf ${RAINLOOP_PATH}
    fi
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
        apt remove ghostscript unattended-upgrades -y
    else
        yum remove ghostscript -y
    fi
}

special_fstab(){
    if [ "${PROVIDER}" = 'vultr' ]; then 
        sed -ie '/tmp/ s/^#*/#/' /etc/fstab
    fi    
}

rmdummy(){
    rm -f ${NOWPATH}/cyberpanel.sh
    rm -rf ${NOWPATH}/install*
    rm -rf /usr/local/CyberCP/.idea/
    rm -f /etc/profile.d/cyberpanel.sh
}    

main(){
    START_TIME="$(date -u +%s)"
    check_os
    providerck
    upgrade
    install_basic_pkg
    install_cyberpanel
    rm_agpl_pkg
    special_fstab
    rmdummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}

main
exit 0

