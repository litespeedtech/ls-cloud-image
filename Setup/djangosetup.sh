#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Django setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2021
# @Version: 1.2
# *********************************************************************/
LSWSFD='/usr/local/lsws'
USER='nobody'
GROUP='nogroup'
FIREWALLLIST="22 80 443"
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
LSWSVHCONF="${LSWSFD}/conf/vhosts/Example/vhconf.conf"
WSGINAME='wsgi-lsapi-1.8'
PROJNAME='demo'
PROJAPPNAME='app'
VHDOCROOT='/usr/local/lsws/Example/html'
DEMOPROJECT="${VHDOCROOT}/${PROJNAME}"
DEMOSETTINGS="${DEMOPROJECT}/${PROJNAME}/settings.py"
ALLERRORS=0
DJ_VER='>=3.2,<4.0'
PY_V=''
V_ENV='ON'
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

linechange(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    if [ -n "${LINENUM}" ] && [ "${LINENUM}" -eq "${LINENUM}" ] 2>/dev/null; then
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
        OSNAMEVER=''
        cat /etc/lsb-release | grep "DISTRIB_RELEASE=18." >/dev/null
        if [ ${?} = 0 ] ; then
            OSNAMEVER=UBUNTU18
        fi
        cat /etc/lsb-release | grep "DISTRIB_RELEASE=20." >/dev/null
        if [ $? = 0 ] ; then
            OSNAMEVER=UBUNTU20
        fi             
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

centos_install_python(){
    echoG 'Install python'
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
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        if [ -e sqlite3 ]; then 
            echoG 'Make success, replacing sqlite bin file'
            if [ -e /usr/bin/sqlite3 ]; then
                mv /usr/bin/sqlite3 /usr/bin/sqlite3.bk
            fi    
            mv sqlite3 /usr/bin/
            export LD_LIBRARY_PATH="/usr/local/lib"
            echo 'export LD_LIBRARY_PATH="/usr/local/lib"' >> /etc/profile
            echoG 'Finished sqlite3 compile'
        else
            echoR 'Make Failed'    
        fi
    else 
        echoR 'Configure Failed'   
    fi     
}

ubuntu_install_python(){
    echoG 'Install python'
    apt-get install python3-pip -y > /dev/null 2>&1
    apt-get install python3-dev -y > /dev/null 2>&1
    apt-get install virtualenv -y > /dev/null 2>&1
    apt-get install socat -y > /dev/null 2>&1
    apt-get install build-essential -y > /dev/null 2>&1
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
    add-apt-repository universe > /dev/null 2>&1
    if [ "${OSNAMEVER}" = 'UBUNTU18' ]; then
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

install_wsgi(){
    echoG 'Build wsgi'
    curl http://www.litespeedtech.com/packages/lsapi/${WSGINAME}.tgz -so /opt/${WSGINAME}.tgz
    tar zxf /opt/${WSGINAME}.tgz -C /opt/
    cd /opt/${WSGINAME}/
    python3 ./configure.py | grep -i Done > /dev/null 2>&1
    if [ ${?} = 0 ]; then  
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

centos_install_wsgi(){
    install_wsgi
}

ubuntu_install_wsgi(){
    install_wsgi
}

config_venv_ols(){
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
  binPath                 ${LSWSFD}/fcgi-bin/lswsgi
  appType                 wsgi
  startupFile             ${PROJNAME}/wsgi.py
  env                     PYTHONPATH=${VHDOCROOT}/lib/${PY_V}:${VHDOCROOT}/${PROJNAME}
  env                     LS_PYTHONBIN=${VHDOCROOT}/bin/python
  addDefaultCharset       off
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
  logLevel                0
}

END
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
  binPath                 ${LSWSFD}/fcgi-bin/lswsgi
  appType                 wsgi
  startupFile             ${PROJNAME}/wsgi.py
  addDefaultCharset       off
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
  logLevel                0
}

END
}

centos_set_ols(){
    if [ "${V_ENV}" = 'ON' ]; then
        config_venv_ols
    else    
        config_ols
    fi    
}    

ubuntu_set_ols(){
    if [ "${V_ENV}" = 'ON' ]; then
        config_venv_ols
    else    
        config_ols
    fi 
} 

get_envpy_ver(){
    PY_V="$(ls ${VHDOCROOT}/lib/ | head -1)"
}

centos_set_env(){
    if [ "${V_ENV}" = 'ON' ]; then
        echoG 'Setting django venv'
        virtualenv --system-site-packages -p /usr/bin/python3 ${VHDOCROOT} > /dev/null 2>&1
        if [ ${?} = 1 ]; then 
            echoR 'Create virtualenv failed'
        fi
        echoG 'Source'
        source ${VHDOCROOT}/bin/activate
    fi
    pip3 install "django${DJ_VER}" > /dev/null 2>&1
}

ubuntu_set_env(){
    if [ "${V_ENV}" = 'ON' ]; then
        echoG 'Setting django venv'
        virtualenv --system-site-packages -p python3 ${VHDOCROOT} > /dev/null 2>&1
        if [ ${?} = 1 ]; then 
            echoR 'Create virtualenv failed'
        fi    
        echoG 'Source'
        source ${VHDOCROOT}/bin/activate
    fi
    pip3 install -I "django${DJ_VER}" > /dev/null 2>&1
}

app_setup(){
    cd ${VHDOCROOT}
    echoG 'Start project'
    django-admin startproject ${PROJNAME}
    cd ${DEMOPROJECT}
    echoG 'Start app'
    python3 manage.py startapp ${PROJAPPNAME}
 
    echoG 'update settings'
    NEWKEY="ALLOWED_HOSTS = ['*']"
    linechange 'ALLOWED_HOST' ${DEMOSETTINGS} "${NEWKEY}"
    
    cat >> ${DEMOSETTINGS} <<END 
STATIC_ROOT = '${DEMOPROJECT}/public/static'
END
    echoG 'Collect files'
    mkdir -p ${DEMOPROJECT}/public/static
    python3 manage.py collectstatic > /dev/null 2>&1
    python3 manage.py migrate > /dev/null 2>&1

    echoG 'update views'
    cat > "${DEMOPROJECT}/${PROJAPPNAME}/views.py" <<END 
from django.shortcuts import render
from django.http import HttpResponse

def index(request):
    return HttpResponse("Hello, world!")
END

    echoG 'Update URLs'
    cat > "${DEMOPROJECT}/${PROJNAME}/urls.py" <<END 
"""demo URL Configuration

The \`urlpatterns\` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/3.0/topics/http/urls/
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
    if [ "${V_ENV}" = 'ON' ]; then
        deactivate
    fi    
    echoG 'Finish django'
}

centos_set_app(){
    get_envpy_ver
    app_setup
}

ubuntu_set_app(){
    get_envpy_ver
    app_setup
}

acme_folder(){
    mkdir -p ${VHDOCROOT}/.well-known
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
    if [ ${PROVIDER} = 'oracle' ]; then 
        oci_iptables
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
    if [ ${PROVIDER} = 'oracle' ]; then 
        oci_iptables
    fi    
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
    centos_install_python
    centos_install_certbot
    centos_install_wsgi
    centos_install_firewall
}

centos_main_config(){
    centos_set_env
    centos_set_app
    centos_set_ols
    centos_config_firewall
}

ubuntu_main_install(){    
    ubuntu_install_basic
    ubuntu_install_ols
    ubuntu_install_python
    ubuntu_install_certbot
    ubuntu_install_wsgi
}    

ubuntu_main_config(){
    ubuntu_set_env
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

case ${1} in
    -NOVENV|--no-venv)
        V_ENV='OFF'
        ;;
esac

main
exit 0    
