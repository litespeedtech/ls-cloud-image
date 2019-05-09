#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0
# *********************************************************************/

CLDINITPATH='/var/lib/cloud/scripts/per-instance'

check_os(){
if [ -f /etc/redhat-release ] ; then
    OSNAME=centos
elif [ -f /etc/lsb-release ] ; then
    OSNAME=ubuntu    
elif [ -f /etc/debian_version ] ; then
    OSNAME=debian
fi         
}
check_os

setup(){
    ### per-instance.sh
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Cloud-init/per-instance.sh \
    -o ${CLDINITPATH}
    chmod +x ${CLDINITPATH}
    
    ### domainsetup.sh
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Setup/domainsetup.sh \
    -o /opt/domainsetup.sh
    chmod +x /opt/domainsetup.sh
}
cleanup (){
  # IF CyberPanel is installed on Ubuntu we need to remove firewalld
  if [ -d /usr/local/CyberCP ] && [ "${OSNAME}" != 'centos' ]; then
    sudo apt-get remove firewalld -y > /dev/null 2>&1
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
  #aws
  rm -f /var/log/amazon/ssm/*
  #component log
  rm -f /usr/local/lscp/logs/*
  rm -f /var/log/mail.log*
  rm -f /var/log/mail.err
  rm -f /var/log/letsencrypt/letsencrypt.log*
  rm -f /var/log/fail2ban.log* 
  rm -f /var/log/mysql/error.log
  rm -f /etc/mysql/debian.cnf
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
  if [ "$(cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ] && [ -d /home/ubuntu ]; then
    rm -f /home/ubuntu/.mysql_history
    rm -f /home/ubuntu/.bash_history
    rm -f /home/ubuntu/.ssh/authorized_keys   
    rm -f /home/ubuntu/.litespeed_password
  fi  
  if [ "$(dmidecode -s bios-vendor)" = 'Google' ]; then
    allhmfolder=$(ls /home/)
    for i in ${allhmfolder[@]}; do
      if [ "${i}" != 'ubuntu' ]; then
        rm -rf "/home/${i}"
      fi
    done  
  fi
}

setup
cleanup
rm -- "$0"
exit 0