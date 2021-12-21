#!/bin/bash
# /********************************************************************
# LiteSpeed domain setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2021
# *********************************************************************/
DOMAIN=''
WWW_DOMAIN=''
DOCHM='/var/www/html'
LSDIR='/usr/local/lsws'
WEBCF="${LSDIR}/conf/httpd_config.conf"
if [ -e "${LSDIR}/conf/vhosts/wordpress/vhconf.conf" ]; then
    VHNAME='wordpress'
elif [ -e "${LSDIR}/conf/vhosts/classicpress/vhconf.conf" ]; then
    VHNAME='classicpress'
elif [ -e "${LSDIR}/conf/vhosts/joomla/vhconf.conf" ]; then
    VHNAME='joomla'   
else
    VHNAME='Example'
    DOCHM="${LSDIR}/${VHNAME}/html"
fi
LSVHCFPATH="${LSDIR}/conf/vhosts/${VHNAME}/vhconf.conf"
UPDATELIST='/var/lib/update-notifier/updates-available'
BOTCRON='/etc/cron.d/certbot'
WWW='FALSE'
UPDATE='TRUE'
OSNAME=''

echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}

echoB(){
    echo -e "\033[1;34m${1}\033[0m"
}

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
        BOTCRON='/etc/crontab'
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}

providerck()
{
    if [ -e /sys/devices/virtual/dmi/id/product_uuid ] && [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then 
        PROVIDER='aws'
    elif [ -d /proc/vz/ ]; then
        PROVIDER='vm'
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'      
    elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
        PROVIDER='do'
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

get_ip()
{
    if [ ${PROVIDER} = 'vm' ]; then 
        MY_IP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0") 
    elif [ ${PROVIDER} = 'aws' ]; then 
        MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) 
    elif [ ${PROVIDER} = 'google' ]; then 
        MY_IP=$(curl -s -H "Metadata-Flavor: Google" \
        http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)    
    elif [ ${PROVIDER} = 'aliyun' ]; then
        MY_IP=$(curl -s http://100.100.100.200/latest/meta-data/eipv4)   
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        MY_IP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")    
    else
        MY_IP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0") 
  fi    
}

domainhelp(){
    echoB "To visit your apps by domain instead of IP, please enter a valid domain."
    echoB "If you don't have one yet, you may cancel this process by pressing CTRL+C and continuing to SSH."
    echoB "This prompt will open again the next time you log in, and will continue to do so until you finish the setup."
    echoB "Make sure the domain's DNS record has been properly pointed to this server."
    echo -e "Enter the root domain only, then the system will add both the root domain and the www domain for you."
}

restart_lsws(){
    ${LSDIR}/bin/lswsctrl stop >/dev/null 2>&1
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws >/dev/null 2>&1    
}   

domain_filter(){
    DOMAIN="${1}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#ftp://}"
    DOMAIN="${DOMAIN#scp://}"
    DOMAIN="${DOMAIN#scp://}"
    DOMAIN="${DOMAIN#sftp://}"
    DOMAIN=${DOMAIN%%/*}
}

domaininput(){
    printf "%s" "Your domain: "
    read DOMAIN
    if [ -z "${DOMAIN}" ] ; then
        echo -e "\nPlease input a valid domain\n"
        exit 1
    fi
    domain_filter ${DOMAIN}
    echo -e "The domain you put is: \e[31m${DOMAIN}\e[39m"
    printf "%s"  "Please verify it is correct. [y/N] "
}

duplicateck(){
    grep "${1}" ${2} >/dev/null 2>&1
}

www_domain(){
    CHECK_WWW=$(echo ${1} | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]] ; then
        DOMAIN=$(echo ${1} | cut -c 5-)
    else
        DOMAIN=${1}
    fi
    WWW_DOMAIN="www.${DOMAIN}"
}

domainadd(){
    duplicateck ${DOMAIN} ${WEBCF}
    if [ ${?} = 1 ]; then 
        if [ ${PROVIDER} = 'do' ] && [ "${VHNAME}" = 'wordpress' ]; then
            sed -i 's|wordpress '${MY_IP}'|wordpress '${MY_IP}', '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}
        elif [ ${PROVIDER} = 'do' ] && [ "${VHNAME}" = 'classicpress' ]; then
            sed -i 's|classicpress '${MY_IP}'|classicpress '${MY_IP}', '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF} 
        elif [ ${PROVIDER} = 'do' ] && [ "${VHNAME}" = 'joomla' ]; then
            sed -i 's|joomla '${MY_IP}'|joomla '${MY_IP}', '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}                       
        elif [ ${PROVIDER} = 'do' ]; then
            sed -i 's|Example '${MY_IP}'|Example '${MY_IP}', '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}
        elif [ "${VHNAME}" = 'wordpress' ]; then
            sed -i 's|wordpress \*|wordpress \*, '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}
        elif [ "${VHNAME}" = 'classicpress' ]; then
            sed -i 's|classicpress \*|classicpress \*, '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}   
        elif [ "${VHNAME}" = 'joomla' ]; then
            sed -i 's|joomla \*|joomla \*, '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}                     
        else
            sed -i 's|Example \*|Example \*, '${DOMAIN}', '${WWW_DOMAIN}' |g' ${WEBCF}
        fi
    fi
    restart_lsws
    echoG "\nDomain has been added into OpenLiteSpeed listener.\n"
}

domainverify(){
    curl -Is http://${DOMAIN}/ | grep -i 'LiteSpeed\|cloudflare' > /dev/null 2>&1
    if [ ${?} = 0 ]; then
        echoG "[OK] ${DOMAIN} is accessible."
        TYPE=1
        curl -Is http://${WWW_DOMAIN}/ | grep -i 'LiteSpeed\|cloudflare' > /dev/null 2>&1
        if [ ${?} = 0 ]; then
            echoG "[OK] ${WWW_DOMAIN} is accessible."
            TYPE=2
        else
            echo "${WWW_DOMAIN} is inaccessible." 
        fi        
    else
        echo "${DOMAIN} is inaccessible, please verify!"; exit 1
    fi
}

main_domain_setup(){
    domainhelp
    while true; do
        domaininput
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
            www_domain ${DOMAIN}
            domainadd
            break
        fi
    done    
}
emailinput(){
    CKREG="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
    printf "%s" "Please enter your E-mail: "
    read EMAIL
    if [[ ${EMAIL} =~ ${CKREG} ]] ; then
      echo -e "The E-mail you entered is: \e[31m${EMAIL}\e[39m"
      printf "%s"  "Please verify it is correct: [y/N] "
    else
      echo -e "\nPlease enter a valid E-mail, exit setup\n"; exit 1
    fi  
}

rstlswscron(){
    echo '0 0 * * 3 root systemctl restart lsws' | sudo tee -a ${BOTCRON} > /dev/null
}

certbothook(){
    grep 'certbot.*restart lsws' ${BOTCRON} >/dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG 'Web Server Restart hook already set!'
    else
        if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ] ; then
            sed -i 's/0.*/&  --deploy-hook "systemctl restart lsws"/g' ${BOTCRON}
        elif [ "${OSNAME}" = 'centos' ]; then
            if [ "${OSVER}" = '7' ]; then
                echo "0 0,12 * * * root python -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q --deploy-hook 'systemctl restart lsws'" \
                | sudo tee -a ${BOTCRON} > /dev/null
            elif [ "${OSVER}" = '8' ]; then
                echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && /usr/local/bin/certbot renew -q --deploy-hook 'systemctl restart lsws'" \
                | sudo tee -a ${BOTCRON} > /dev/null
            else
                echoY 'Please check certbot crontab'
            fi
        fi    
        rstlswscron
        grep 'restart lsws' ${BOTCRON} > /dev/null 2>&1
        if [ ${?} = 0 ]; then 
            echoG 'Certbot hook update success'
        else 
            echoY 'Please check certbot crond'
        fi
    fi       
}

lecertapply(){
    if [ ${TYPE} = 1 ]; then
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${DOMAIN}
    elif [ ${TYPE} = 2 ]; then
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${DOMAIN} -d ${WWW_DOMAIN}
    else
        echo 'Unknown type!'; exit 2    
    fi
    if [ ${?} -eq 0 ]; then
        echo "vhssl  {
            keyFile                 /etc/letsencrypt/live/${DOMAIN}/privkey.pem
            certFile                /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
            certChain               1
        }" >> ${LSVHCFPATH}

        echoG "\ncertificate has been successfully installed..."
    else
        echo "Oops, something went wrong..."
        exit 1
    fi
}

force_https() {
    if [ "${VHNAME}" = 'wordpress' ] || [ "${VHNAME}" = 'classicpress' ] || [ "${VHNAME}" = 'joomla' ]; then 
        duplicateck "RewriteCond %{HTTPS} on" "${DOCHM}/.htaccess"
        if [ ${?} = 1 ]; then 
            echo "$(echo '
### Forcing HTTPS rule start       
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
### Forcing HTTPS rule end
            ' | cat - ${DOCHM}/.htaccess)" > ${DOCHM}/.htaccess
        fi
    else 
        sed -i '/^  logLevel                0/a\ \ rules                   <<<END_rules \
RewriteCond %{SERVER_PORT} 80\nRewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]\
\ \ END_rules' ${LSVHCFPATH}   
    fi    
    echoG "Force HTTPS rules has been added success."
}

endsetup(){
    sed -i '/domainsetup.sh/d' /etc/profile
}

aptupgradelist() {
    PACKAGE=$(cat ${UPDATELIST} | awk '{print $1}' | sed -n 2p)
    SECURITY=$(cat ${UPDATELIST} | awk '{print $1}' | sed -n 3p)
    if [ "${PACKAGE}" = '0' ] && [ "${SECURITY}" = '0' ]; then 
        UPDATE='FALSE'    
    fi    
}

yumupgradelist(){
    PACKAGE=$(yum check-update | grep -v '*\|Load*\|excluded' | wc -l)
    if [ "${PACKAGE}" = '0' ]; then 
        UPDATE='FALSE'
    fi    
}

aptgetupgrade() {
    apt-get update > /dev/null 2>&1
    echo -ne '#####                     (33%)\r'
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade > /dev/null 2>&1
    echo -ne '#############             (66%)\r'
    if [ -f /etc/apt/sources.list.d/mariadb_repo.list ]; then
        ### an apt bug
        mv  /etc/apt/sources.list.d/mariadb_repo.list /tmp/
    fi    
    #DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade > /dev/null 2>&1
    echo -ne '####################      (99%)\r'
    apt-get clean > /dev/null 2>&1
    apt-get autoclean > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'
}

yumupgrade(){
    echo -ne '#                         (5%)\r'
    yum update -y > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'
}
main_cert_setup(){
    printf "%s"   "Do you wish to issue a Let's encrypt certificate for this domain? [y/N] "
    read TMP_YN
    if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
        domainverify
        while true; do 
            emailinput
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                lecertapply
                break
            fi
        done   
        certbothook 
        printf "%s"   "Do you wish to force HTTPS rewrite rule for this domain? [y/N] "
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
            force_https
        fi
        restart_lsws
    fi        
}

main_upgrade(){
    if [ "${OSNAME}" = 'ubuntu' ]; then
        if [ ${PROVIDER} != 'aliyun' ]; then
            aptupgradelist
        fi    
    else
        yumupgradelist
    fi    
    #if [ "${UPDATE}" = 'TRUE' ]; then
        printf "%s"   "Do you wish to update the system now? This will update the web server as well. [Y/n]? "
        read TMP_YN
        if [[ ! "${TMP_YN}" =~ ^(n|N) ]]; then
            echoG "Update Starting..." 
            if [ "${OSNAME}" = 'ubuntu' ]; then 
                aptgetupgrade
            else
                yumupgrade
            fi    
            echoG "\nUpdate complete" 
        fi    
    #else
    #    echoG 'Your system is up to date'
    #fi
    if [ ! -d /usr/local/CyberCP ]; then
        echoG "\nEnjoy your accelarated OpenLiteSpeed server!\n"
    else
        echoG "\nEnjoy your accelarated CyberPanel server!\n"
    fi    
}

main(){
    check_os
    providerck
    get_ip
    if [ ! -d /usr/local/CyberCP ]; then
        main_domain_setup
        main_cert_setup
    fi   
    main_upgrade
    endsetup
}
main
rm -- "$0"
exit 0
