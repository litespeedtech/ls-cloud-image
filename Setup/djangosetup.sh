#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Django setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0.1
# *********************************************************************/
LSWSFD='/usr/local/lsws'
PHPVER=73
USER='nobody'
GROUP='nogroup'
FIREWALLLIST="22 80 443"
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
LSWSVHCONF="${LSWSFD}/conf/vhosts/Example/vhconf.conf"
WSGINAME='wsgi-lsapi-1.5'
PROJNAME='demo'
PROJAPPNAME='app'
VHDOCROOT='/usr/local/lsws/Example/html'
DEMOPROJECT="${VHDOCROOT}/${PROJNAME}"
DEMOSETTINGS="${DEMOPROJECT}/${PROJNAME}/settings.py"
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
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}
check_os
providerck()
{
  if [ -e /sys/devices/virtual/dmi/id/product_uuid ] && [ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ]; then 
    PROVIDER='aws'
  elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
    PROVIDER='google'      
  elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
    PROVIDER='do'
  elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
    PROVIDER='aliyun'  
  elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
    PROVIDER='azure'     
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

install_basic_pkg(){
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install wget > /dev/null 2>&1
    else  
        apt-get -y install wget > /dev/null 2>&1
    fi
}

### Start
installols(){
    cd /tmp/; wget -q https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh
    chmod +x ols1clk.sh
    echo 'Y' | bash ols1clk.sh \
    --lsphp ${PHPVER}
}

installpkg(){
    echoG 'Install packages'
    if [ "${OSNAME}" = 'centos' ]; then 
        yum install python36-devel -y > /dev/null 2>&1
        yum install python36-pip -y > /dev/null 2>&1
        yum groupinstall "Development Tools" -y > /dev/null 2>&1
        yum install wget -y > /dev/null 2>&1
        pip3 install virtualenv > /dev/null 2>&1
        ### Install latest sqlite version
        echoG 'Install latest sqlite'
        LASTSQLV=$(curl -s https://www.sqlite.org/download.html | grep '/sqlite-autoconf.*gz' | awk -F "'" '{print $4}')
        wget -q https://www.sqlite.org/${LASTSQLV} -P /opt/
        cd /opt/
        tar -zxf sqlite-autoconf-*.tar.gz
        rm -f sqlite-autoconf-*.tar.gz
        cd sqlite-autoconf-*
        echoG 'Compiling from source code'
        ./configure > /dev/null 2>&1
        if [ -e Makefile ]; then 
            make && sudo make install > /dev/null 2>&1
            if [ -e sqlite3 ]; then 
                echoG 'Make success, replacing sqlite bin file'
                mv /usr/bin/sqlite3 /usr/bin/sqlite3.bk
                mv sqlite3 /usr/bin/
                ### export lib
                export LD_LIBRARY_PATH="/usr/local/lib"
                echo 'export LD_LIBRARY_PATH="/usr/local/lib"' >> /etc/profile
                echoG 'Finished sqlite3 compile'
            else
                echoR 'Make Failed'    
            fi
        else 
            echoR 'Configure Failed'   
        fi     
    else 
        apt-get install python3-pip -y > /dev/null 2>&1
        apt-get install python3-dev -y > /dev/null 2>&1
        apt-get install virtualenv -y > /dev/null 2>&1
        apt-get install socat -y > /dev/null 2>&1
        apt-get install build-essential -y > /dev/null 2>&1
    fi 

    ### CertBot
    echoG "Install CertBot" 
    if [ "${OSNAME}" = 'centos' ]; then 
        if [ ${OSVER} = 8 ]; then
            wget -q https://dl.eff.org/certbot-auto
            mv certbot-auto /usr/local/bin/certbot
            chown root /usr/local/bin/certbot
            chmod 0755 /usr/local/bin/certbot
            echo "y" | /usr/local/bin/certbot > /dev/null 2>&1
        else
            yum -y install certbot  > /dev/null 2>&1
        fi
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

installwsgi(){
    echoG 'Build wsgi'
    curl http://www.litespeedtech.com/packages/lsapi/${WSGINAME}.tgz -so /opt/${WSGINAME}.tgz
    tar zxf /opt/${WSGINAME}.tgz -C /opt/
    cd /opt/${WSGINAME}/
    python3 ./configure.py | grep -i Done > /dev/null 2>&1
    if [ $? = 0 ]; then  
        make > /dev/null 2>&1
        if [ -e 'lswsgi' ]; then 
            cp lswsgi ${LSWSFD}/fcgi-bin/    
            echoG 'Finish Build wsgi'
            cd /opt
            rm -rf /opt/${WSGINAME}*
        else
            echoR 'Failed to Make' 
        fi    
    else
        echoR 'Failed to configure'    
    fi
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
  binPath                 ${LSWSFD}/fcgi-bin/lswsgi
  appType                 wsgi
  startupFile             ${PROJNAME}/wsgi.py
  env                     PYTHONHOME=${VHDOCROOT}/
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
    echoG 'Setting django venv'
    virtualenv --system-site-packages -p python3 ${VHDOCROOT} > /dev/null 2>&1
    if [ $? = 1 ]; then 
        echoR 'Create virtualenv failed'
    fi    
    echoG 'Source'
    source ${VHDOCROOT}/bin/activate
    ### Install Django
    if [ "${OSNAME}" = 'centos' ]; then 
        ### Currently CentOS 7 + 2.2 have 500 error 
        pip3 install -I django==2.1.8> /dev/null 2>&1
    elif [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
        pip3 install -I django > /dev/null 2>&1
    fi 
    cd ${VHDOCROOT}
    echoG 'Start project'
    django-admin startproject ${PROJNAME}
    cd ${DEMOPROJECT}
    echoG 'Start app'
    python3 manage.py startapp ${PROJAPPNAME}
 
    ### Update Settings
    echoG 'update settings'
    NEWKEY="ALLOWED_HOSTS = ['*']"
    linechange 'ALLOWED_HOST' ${DEMOSETTINGS} "${NEWKEY}"
    
    cat >> ${DEMOSETTINGS} <<END 
STATIC_ROOT = '${DEMOPROJECT}/public/static'
END
    ### Collect static files
    echoG 'Collect files'
    mkdir -p ${DEMOPROJECT}/public/static
    python manage.py collectstatic > /dev/null 2>&1
    python manage.py migrate > /dev/null 2>&1

    ### Demo view
    echoG 'update views'
    cat > "${DEMOPROJECT}/${PROJAPPNAME}/views.py" <<END 
from django.shortcuts import render
from django.http import HttpResponse

def index(request):
    return HttpResponse("Hello, world!")
END

    ### Demo Urls
    echoG 'Update URLs'
    cat > "${DEMOPROJECT}/${PROJNAME}/urls.py" <<END 
"""demo URL Configuration

The \`urlpatterns\` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/2.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path
from app import views

urlpatterns = [
    path('', views.index, name='index'),
    path('admin/', admin.site.urls),
]
END
    ### Exit venv
    deactivate
    echoG 'Finish django'
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
    install_basic_pkg
    installols
    installpkg
    installwsgi
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