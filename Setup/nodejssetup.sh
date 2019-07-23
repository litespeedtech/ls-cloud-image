#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed NodeJS setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0
# *********************************************************************/

LSWSFD='/usr/local/lsws'
PHPVER=73
USER='nobody'
GROUP='nogroup'
FIREWALLLIST="22 80 443"
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
LSWSVHCONF="${LSWSFD}/conf/vhosts/Example/vhconf.conf"
PROJNAME='node'
VHDOCROOT='/usr/local/lsws/Example/html'
DEMOPROJECT="${VHDOCROOT}/${PROJNAME}"
ALLERRORS=0
NOWPATH=$(pwd)

### Tools
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
linechange(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

### ENV
check_os()
{
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}
check_os
providerck()
{
  if [ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ] && [ -d /home/ubuntu ]; then 
    PROVIDER='aws'
  elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
    PROVIDER='google'      
  elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
    PROVIDER='do'
  elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
    PROVIDER='aliyun'  
  else
    PROVIDER='undefined'  
  fi
}
providerck

changeowner(){
  chown -R ${USER}:${GROUP} ${DEMOPROJECT}
}

### Upgrade
systemupgrade() {
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
}

### Start
installols(){
    echo 'Y' | bash <( curl -k https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh ) \
    --lsphp ${PHPVER}
}

installpkg(){
    echoG 'Install packages'
    ### Install nodejs with version 10 by using EPEL repository
    curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - > /dev/null 2>&1
    if [ "${OSNAME}" = 'centos' ]; then 
        yum install nodejs -y > /dev/null 2>&1
    else 
        apt-get install nodejs -y > /dev/null 2>&1
    fi 
    echoG "NodeJS: $(node --version)"
    echoG "NPM:    $(npm --version)"

    ### CertBot
    echoG "Install CertBot" 
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install certbot  > /dev/null 2>&1
    else 
        add-apt-repository universe > /dev/null 2>&1
        echo -ne '\n' | add-apt-repository ppa:certbot/certbot > /dev/null 2>&1
        apt-get update > /dev/null 2>&1
        apt-get -y install certbot > /dev/null 2>&1

    fi 
    if [ -e /usr/bin/certbot ]; then 
        echoG 'Install CertBot finished'
    else 
        echoR 'Please check CertBot'    
    fi       

    echoG 'Finish packages'
}

configols(){
   echoG 'Setting Web Server config'
    ### change doc root to landing page, setup phpmyadmin context
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
  keepDays                30
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
  location                ${VHDOCROOT}/
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
    service lsws restart
}


appsetup(){
    ### Create project folder
    mkdir -p ${DEMOPROJECT}
    cat > "${DEMOPROJECT}/app.js" <<END 
const http = require('http');

const hostname = '127.0.0.1';
const port = 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello World! Form OpenLiteSpeed NodeJS\n');
});

server.listen(port, hostname, () => {
  console.log(\`Server running at http://${hostname}:${port}/\`);
});
END

}

firewalladd(){
    echoG 'Setting Firewall'
    if [ "${OSNAME}" = 'centos' ]; then 
        if [ ! -e /usr/sbin/firewalld ]; then 
            yum -y install firewalld > /dev/null 2>&1
        fi
        service firewalld start > /dev/null 2>&1
        systemctl enable firewalld > /dev/null 2>&1
        for PORT in ${FIREWALLLIST}; do 
            firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
        done 
        firewall-cmd --reload > /dev/null 2>&1
        firewall-cmd --list-all | grep 80 > /dev/null 2>&1
        if [ $? = 0 ]; then 
            echoG 'firewalld rules setup success'
        else 
            echoR 'Please check firewalld rules'    
        fi 
    else 
        ufw status verbose | grep inactive > /dev/null 2>&1
        if [ $? = 0 ]; then 
            for PORT in ${FIREWALLLIST}; do
                ufw allow ${PORT} > /dev/null 2>&1
            done    
            echo "y" | ufw enable > /dev/null 2>&1

            ufw status | grep '80.*ALLOW' > /dev/null 2>&1
            if [ $? = 0 ]; then 
                echoG 'firewalld rules setup success'
            else 
                echoR 'Please check ufw rules'    
            fi 
        else
            echoG "ufw already enabled"    
        fi
    fi
}

rmdummy(){
    echoG 'Remove dummy file'
    rm -f "${NOWPATH}/example.csr" "${NOWPATH}/privkey.pem"
    echoG 'Finished dummy file'
}

### Main
main(){
    START_TIME="$(date -u +%s)"
    systemupgrade
    installols
    installpkg
    appsetup
    configols
    changeowner
    firewalladd
    rmdummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}
main
#echoG 'Auto remove script itself'
#rm -- "$0"
exit 0    