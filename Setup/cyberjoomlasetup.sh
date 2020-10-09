#!/bin/bash
# /********************************************************************
# LiteSpeed CyberPanel Joomla setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2020-2021
# @Version: 1.0.0
# *********************************************************************/

NOWPATH=$(pwd)
APPNAME_PATH='/opt/.app_name'

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

app_file(){
    echoG 'Setup App Name file'
    if [ ! -e "${APPNAME_PATH}" ]; then
        touch "${APPNAME_PATH}"
        echo 'cyberpanel-joomla' > "${APPNAME_PATH}"
    else
        echoR "${APPNAME_PATH} exist, please check!"   
    fi
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

rmdummy(){
    rm -f ${NOWPATH}/cyberpanel.sh
    rm -rf ${NOWPATH}/install*
    rm -rf /usr/local/CyberCP/.idea/
    rm -f /etc/profile.d/cyberpanel.sh
}    

main(){
    START_TIME="$(date -u +%s)"
    check_os
    upgrade
    install_basic_pkg
    install_cyberpanel
    app_file
    rm_agpl_pkg
    rmdummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}

main
exit 0

