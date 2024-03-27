#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed NodeJS setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2024
# @Version: 1.2
# *********************************************************************/
LSWSFD='/usr/local/lsws'
USER='nobody'
GROUP='nogroup'
FIREWALLLIST="22 80 443"
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
LSWSVHCONF="${LSWSFD}/conf/vhosts/Example/vhconf.conf"
PROJNAME='node'
VHDOCROOT='/usr/local/lsws/Example/html'
DEMOPROJECT="${VHDOCROOT}/${PROJNAME}"
ALLERRORS=0
NODEJSV='18'
NOWPATH=$(pwd)

echoY(){
    echo -e "\033[38;5;148m${1}\033[39m"
}

echoG(){
    echo -e "\033[38;5;71m${1}\033[39m"
}

echoR(){
    echo -e "\033[38;5;203m${1}\033[39m"
}

linechange(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu  
        OSNAMEVER="UBUNTU$(lsb_release -sr | awk -F '.' '{print $1}')"
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}

check_provider(){
    if [ -e /sys/devices/virtual/dmi/id/product_uuid ] && [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then 
        PROVIDER='aws'
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

change_owner(){
    chown -R ${USER}:${GROUP} ${DEMOPROJECT}
}

centos_sys_upgrade(){
    echoG 'Updating system'
    echo -ne '#                         (5%)\r'
    yum update -y > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'   
}

ubuntu_sys_upgrade(){
    echoG 'Updating system'
    apt-get update > /dev/null 2>&1
    echo -ne '#####                     (33%)\r'
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade > /dev/null 2>&1
    echo -ne '#############             (66%)\r'
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade > /dev/null 2>&1
    echo -ne '####################      (99%)\r'
    apt-get clean > /dev/null 2>&1
    apt-get autoclean > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'    
}    

centos_install_basic(){
    yum -y install wget > /dev/null 2>&1
}

ubuntu_install_basic(){
    apt-get -y install wget > /dev/null 2>&1
}

install_ols(){
    cd /tmp/; wget -q https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh
    chmod +x ols1clk.sh
    echo 'Y' | bash ols1clk.sh 
}

centos_install_ols(){
    install_ols
}

ubuntu_install_ols(){
    install_ols
}

centos_install_nodejs(){
    echoG 'Install nodejs'
    ### Install nodejs with version 12 by using EPEL repository
    curl -sL https://rpm.nodesource.com/setup_${NODEJSV}.x | sudo -E bash - > /dev/null 2>&1
    yum install nodejs -y > /dev/null 2>&1
    echoG "NodeJS: $(node --version)"
    echoG "NPM:    $(npm --version)"
}

ubuntu_install_nodejs(){
    echoG 'Install nodejs'
    ### Install nodejs with version 12 by using EPEL repository
    curl -sL https://deb.nodesource.com/setup_${NODEJSV}.x | sudo -E bash - > /dev/null 2>&1
    apt-get install nodejs -y > /dev/null 2>&1 
    echoG "NodeJS: $(node --version)"
    echoG "NPM:    $(npm --version)"    
}

centos_install_certbot(){
    echoG "Install CertBot"
    if [ ${OSVER} = 8 ]; then
        wget -q https://dl.eff.org/certbot-auto
        mv certbot-auto /usr/local/bin/certbot
        chown root /usr/local/bin/certbot
        chmod 0755 /usr/local/bin/certbot
        echo "y" | /usr/local/bin/certbot > /dev/null 2>&1
    else
        yum -y install certbot  > /dev/null 2>&1
    fi
    if [ -e /usr/bin/certbot ] || [ -e /usr/local/bin/certbot ]; then 
        if [ ! -e /usr/bin/certbot ]; then
            ln -s /usr/local/bin/certbot /usr/bin/certbot
        fi
        echoG 'Install CertBot finished'
    else 
        echoR 'Please check CertBot'    
    fi    
}

ubuntu_install_certbot(){
    echoG "Install CertBot"
    if [ "${OSNAMEVER}" = 'UBUNTU18' ]; then
        add-apt-repository universe > /dev/null 2>&1
        echo -ne '\n' | add-apt-repository ppa:certbot/certbot > /dev/null 2>&1
    fi   
    apt-get update > /dev/null 2>&1
    apt-get -y install certbot > /dev/null 2>&1
    if [ -e /usr/bin/certbot ] || [ -e /usr/local/bin/certbot ]; then 
        if [ ! -e /usr/bin/certbot ]; then
            ln -s /usr/local/bin/certbot /usr/bin/certbot
        fi
        echoG 'Install CertBot finished'
    else 
        echoR 'Please check CertBot'    
    fi
}

restart_lsws(){
    echoG 'Restart LiteSpeed Web Server'
    ${LSWSFD}/bin/lswsctrl stop >/dev/null 2>&1
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws >/dev/null 2>&1
}

config_ols(){
    echoG 'Setting Web Server config'
    cat > ${LSWSVHCONF} <<END 
docRoot                   \$VH_ROOT/html/
enableGzip                1

errorlog \$VH_ROOT/logs/error.log {
  useServer               1
  logLevel                DEBUG
  rollingSize             10M
}

accesslog \$VH_ROOT/logs/access.log {
  useServer               0
  rollingSize             10M
  keepDays                7
  compressArchive         0
}

index  {
  useServer               0
  indexFiles              index.html, index.php
  autoIndex               0
  autoIndexURI            /_autoindex/default.php
}

errorpage 404 {
  url                     /error404.html
}

expires  {
  enableExpires           1
}

accessControl  {
  allow                   *
}

realm SampleProtectedArea {

  userDB  {
    location              conf/vhosts/Example/htpasswd
    maxCacheSize          200
    cacheTimeout          60
  }

  groupDB  {
    location              conf/vhosts/Example/htgroup
    maxCacheSize          200
    cacheTimeout          60
  }
}

context /.well-known/ {
  location                ${VHDOCROOT}/.well-known/
  allowBrowse             1
  addDefaultCharset       off
}

context / {
  type                    appserver
  location                ${VHDOCROOT}/${PROJNAME}/
  binPath                 /usr/bin/node
  appType                 node
  addDefaultCharset       off
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
  logLevel                0
}

END
    echoG 'Finish Web Server config'
}

centos_set_ols(){
    config_ols
}    

ubuntu_set_ols(){
    config_ols
} 

acme_folder(){
    mkdir -p ${VHDOCROOT}/.well-known
}

app_setup(){
    mkdir -p ${DEMOPROJECT}
    cat > "${DEMOPROJECT}/app.js" <<END
const http = require('http');

const hostname = '127.0.0.1';
const port = 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello World! From OpenLiteSpeed NodeJS\n');
});

server.listen(port, hostname, () => {
  console.log(\`Server running at http://\${hostname}:\${port}/\`);
});
END
}

centos_set_app(){
    app_setup
}

ubuntu_set_app(){
    app_setup
}

oci_iptables(){
    if [ -e /etc/iptables/rules.v4 ]; then
        echoG 'Setting Firewall for OCI'
        sed '/^:InstanceServices/r'<(
            echo '-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT'
            echo '-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT'
            echo '-A INPUT -p udp -m state --state NEW -m udp --dport 443 -j ACCEPT'
            echo '-A INPUT -p tcp -m state --state NEW -m tcp --dport 7080 -j ACCEPT'
        ) -i -- /etc/iptables/rules.v4
    fi
}

centos_install_firewall(){
    echoG 'Install Firewall'
    if [ ! -e /usr/sbin/firewalld ]; then 
        yum -y install firewalld > /dev/null 2>&1
    fi
    service firewalld start > /dev/null 2>&1
    systemctl enable firewalld > /dev/null 2>&1
}

centos_config_firewall(){
    echoG 'Setting Firewall'
    for PORT in ${FIREWALLLIST}; do 
        firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
    done 
    firewall-cmd --reload > /dev/null 2>&1
    firewall-cmd --list-all | grep 80 > /dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG 'firewalld rules setup success'
    else 
        echoR 'Please check firewalld rules'
    fi 
}

ubuntu_config_firewall(){
    echoG 'Setting Firewall'
    #ufw status verbose | grep inactive > /dev/null 2>&1
    #if [ ${?} = 0 ]; then 
    for PORT in ${FIREWALLLIST}; do
        ufw allow ${PORT} > /dev/null 2>&1
    done    
    echo "y" | ufw enable > /dev/null 2>&1

    ufw status | grep '80.*ALLOW' > /dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG 'firewalld rules setup success'
    else 
        echoR 'Please check ufw rules'    
    fi 
    #else
    #    echoG "ufw already enabled"    
    #fi
}

rm_dummy(){
    echoG 'Remove dummy file'
    rm -f "${NOWPATH}/example.csr" "${NOWPATH}/privkey.pem"
    echoG 'Finished dummy file'
}

init_check(){
    START_TIME="$(date -u +%s)"
    check_os
    check_provider
}

centos_main_install(){
    centos_install_basic
    centos_install_ols
    centos_install_nodejs
    centos_install_certbot
    centos_install_firewall
}

centos_main_config(){
    centos_set_app
    centos_set_ols
    centos_config_firewall
}

ubuntu_main_install(){    
    ubuntu_install_basic
    ubuntu_install_ols
    ubuntu_install_nodejs
    ubuntu_install_certbot
}    

ubuntu_main_config(){
    ubuntu_set_app
    ubuntu_set_ols
    ubuntu_config_firewall
}

end_message(){
    rm_dummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}

main(){
    init_check
    if [ ${OSNAME} = 'centos' ]; then
        centos_sys_upgrade
        centos_main_install
        centos_main_config
    else
        ubuntu_sys_upgrade
        ubuntu_main_install
        ubuntu_main_config
    fi
    acme_folder
    restart_lsws 
    change_owner
    end_message
}

main
#rm -- "$0"
exit 0    