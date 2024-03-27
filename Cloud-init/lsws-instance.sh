#!/bin/bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2020-2024
# *********************************************************************/
LSDIR='/usr/local/lsws'
BANNERNAME='litespeed'

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        BANNERDST='/etc/profile.d/99-one-click.sh'
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu   
        BANNERDST='/etc/update-motd.d/99-one-click'
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        BANNERDST='/etc/update-motd.d/99-one-click'
    fi        
}


check_provider()
{
    if [ -e /sys/devices/virtual/dmi/id/product_uuid ] && [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then
        PROVIDER='aws'    
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'     
    elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
        PROVIDER='do'
    elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
        PROVIDER='ali'
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        PROVIDER='azure'   
    elif [ -e /etc/oracle-cloud-agent/ ]; then
        PROVIDER='oracle'               
    elif [ -e /root/StackScript ]; then
        if grep -q 'linode' /root/StackScript; then
            PROVIDER='linode'
        fi
    else
        PROVIDER='undefined'
    fi
}


os_home_path()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
        PUBIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
        PUBIP=$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)   
    elif [ ${PROVIDER} = 'ali' ]; then
        HMPATH='/root'
        PUBIP=$(curl http://100.100.100.200/latest/meta-data/eipv4)   
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        HMPATH='/root'
        PUBIP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")        
    else
        HMPATH='/root'
        PUBIP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")
    fi   
}


ct_version()
{
    curl "https://api.quic.cloud/data/1click_ver?t=image&src=aws-lsws" > /dev/null 2>&1
}


setup_banner(){
    if [ ! -e ${BANNERDST} ]; then
        STATUS="$(curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Banner/${BANNERNAME} \
        -o ${BANNERDST} -w "%{http_code}")"  
        if [ ${?} != 0 ] || [ "${STATUS}" != '200' ]; then
            curl -s https://cloud.litespeed.sh/Banner/${BANNERNAME} -o ${BANNERDST}
        fi  
        chmod +x ${BANNERDST}
    fi
}


litespeed_passwordfile(){
    if [ ! -e "${HMPATH}/.litespeed_password" ]; then
        touch "${HMPATH}/.litespeed_password"
    fi
    LSPASSPATH="${HMPATH}/.litespeed_password"
}


gen_lsws_pwd()
{
    ADMIN_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    ENCRYPT_PASS=$(${LSDIR}/admin/fcgi-bin/admin_php5 -q ${LSDIR}/admin/misc/htpasswd.php ${ADMIN_PASS})
}


gen_selfsigned_cert()
{
    SSL_HOSTNAME=example
    csr="${SSL_HOSTNAME}.csr"
    key="${SSL_HOSTNAME}.key"
    cert="${SSL_HOSTNAME}.crt"


    openssl req -new -passin pass:password -passout pass:password -out ${csr} >/dev/null 2>&1 <<csrconf
US
NJ
Virtual
LiteSpeedCommunity
Testing
webadmin
.
.
.
csrconf
    [ -f ${csr} ] && openssl req -text -noout -in ${csr} >/dev/null 2>&1
    openssl rsa -in privkey.pem -passin pass:password -passout pass:password -out ${key} >/dev/null 2>&1
    openssl x509 -in ${csr} -out ${cert} -req -signkey ${key} -days 1000 >/dev/null 2>&1
    rm -f ${SSL_HOSTNAME}.csr
    rm -f privkey.pem
    mv ${SSL_HOSTNAME}.crt ${LSDIR}/conf/${SSL_HOSTNAME}.crt
    mv ${SSL_HOSTNAME}.key ${LSDIR}/conf/${SSL_HOSTNAME}.key      
}


web_admin_update(){
    echo "admin:${ENCRYPT_PASS}" > ${LSDIR}/admin/conf/htpasswd
    echo "admin_pass=${ADMIN_PASS}" > ${LSPASSPATH}
    chmod 600 ${HMPATH}/.litespeed_password
}


rm_dummy(){
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
        rm -f /etc/update-motd.d/00-header
        rm -f /etc/update-motd.d/10-help-text
        rm -f /etc/update-motd.d/50-landscape-sysinfo
        rm -f /etc/update-motd.d/50-motd-news
        rm -f /etc/update-motd.d/51-cloudguest
        rm -f /etc/profile.d/cyberpanel.sh
        if [ -f /etc/legal ]; then
            mv /etc/legal /etc/legal.bk
        fi
        if [ "${PROVIDER}" = 'ali' ]; then
            mv /etc/motd /etc/motd.bk
        fi      
    fi
}


add_hosts(){
    if [ -d /home/ubuntu ]; then
        NEWKEY="127.0.0.1 localhost $(hostname)"
        linechange '127.0.0.1' /etc/hosts "${NEWKEY}"
    fi
}


setupLicense(){
  if [[ -e '/usr/local/lsws/conf/trial.key' ]]; then    
      rm -rf /usr/local/lsws/conf/trial.key  
  fi  
  curl http://license.litespeedtech.com/reseller/trial.key > /usr/local/lsws/conf/trial.key  
  ${LSDIR}/bin/lshttpd -r
  /usr/bin/systemctl restart lsws
}

maincloud(){
    check_os
    check_provider
    os_home_path
    gen_selfsigned_cert
    setup_banner
    litespeed_passwordfile
    ct_version
    gen_lsws_pwd
    web_admin_update
    add_hosts
    setupLicense
    rm_dummy
}

maincloud
rm -f ${CLOUDPERINSTPATH}/per-instance.sh