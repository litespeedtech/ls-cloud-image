#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Rails setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Version: 1.3
# *********************************************************************/
LSWSFD='/usr/local/lsws'
PHPVER=74
USER='nobody'
GROUP='nogroup'
FIREWALLLIST="22 80 443"
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
LSWSVHCONF="${LSWSFD}/conf/vhosts/Example/vhconf.conf"
PROJNAME='demo'
VHDOCROOT='/usr/local/lsws/Example/html'
DEMOPROJECT="${VHDOCROOT}/${PROJNAME}"
CLONE_PATH='/opt'
ALLERRORS=0
RUBYV='3.0.2'
NODEJSV='16'
NOWPATH=$(pwd)
RUBY_PATH='/usr/bin/ruby'
RBENV_PATH='/usr/bin/rbenv'

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
    echo -e '#######################   (100%)\r'   
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
    echo -e '#######################   (100%)\r'    
}    

output_msg(){
    if [ ${1} = 0 ]; then
        echoG "[O] ${2} install"
    else
        echoR "[X] ${2} install, abort!"
        exit 1
    fi  
}

symlink(){
    if [ -e "${1}" ]; then
        if [ -e "${2}" ]; then
            echoG "Backup ${2}"
            mv "${2}" "${2}.bk"
        fi
        ln -s "${1}" "${2}"
        chmod 777 ${2}
    else
        echoR "${1} does not exist, skip!"    
    fi    
}

centos_install_basic(){
    yum -y install wget > /dev/null 2>&1
    yum -y install git > /dev/null 2>&1
    yum -y install git-core zlib zlib-devel gcc-c++ patch readline readline-devel libyaml-devel\
      libffi-devel openssl-devel make bzip2 autoconf automake libtool bison curl sqlite-devel > /dev/null 2>&1
}

ubuntu_install_basic(){
    apt-get -y install wget > /dev/null 2>&1
    apt-get -y install autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev \
      zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libsqlite3-dev > /dev/null 2>&1
    if [ "${OSNAMEVER}" = 'UBUNTU18' ]; then 
        apt-get -y install libgdbm5 > /dev/null 2>&1
    else
        apt-get -y install libgdbm6 > /dev/null 2>&1
    fi    
}

install_ols(){
    echoG '[Start] Install OpenLiteSpeed'
    cd /tmp/; wget -q https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh
    chmod +x ols1clk.sh
    echo 'Y' | bash ols1clk.sh --lsphp ${PHPVER} >/dev/null 2>&1
    echoG '[End] Install OpenLiteSpeed'
}

centos_install_ols(){
    install_ols
}

ubuntu_install_ols(){
    install_ols
}

centos_install_nodejs(){
    echoG 'Install nodejs'
    ### Install nodejs by using EPEL repository
    curl -sL https://rpm.nodesource.com/setup_${NODEJSV}.x | sudo -E bash - > /dev/null 2>&1
    yum clean all > /dev/null 2>&1
    yum install nodejs -y > /dev/null 2>&1
    NODE_V="$(node --version)"
    NPM_V="$(npm --version)"
}

ubuntu_install_nodejs(){
    echoG 'Install nodejs'
    ### Install nodejs by using EPEL repository
    curl -sL https://deb.nodesource.com/setup_${NODEJSV}.x | sudo -E bash - > /dev/null 2>&1
    apt-get install nodejs -y > /dev/null 2>&1
    NODE_V="$(node --version)"
    NPM_V="$(npm --version)"  
}

install_rbenv(){
    echoG 'Install rbenv'
    git clone --quiet https://github.com/rbenv/rbenv.git ${CLONE_PATH}/.rbenv
    git clone --quiet https://github.com/rbenv/ruby-build.git ${CLONE_PATH}/.rbenv/plugins/ruby-build   
    echo "export PATH=\"${CLONE_PATH}/.rbenv/bin:$PATH\"" >> ~/.bashrc
    echo "export PATH=\"${CLONE_PATH}/.rbenv/plugins/ruby-build/bin:$PATH\"" >> ~/.bashrc
    export PATH="${CLONE_PATH}/.rbenv/bin:$PATH"
    export PATH="${CLONE_PATH}/.rbenv/plugins/ruby-build/bin:$PATH"
    eval "$(rbenv init -)"
    echo "RBENV_ROOT=${CLONE_PATH}/.rbenv" >> ~/.bashrc
    export RBENV_ROOT=${CLONE_PATH}/.rbenv
    symlink "${CLONE_PATH}/.rbenv/libexec/rbenv" "${RBENV_PATH}"
    RBEN_V="$(rbenv -v)"
    output_msg "${?}" 'rbenv'
}

install_ruby(){
    echoG 'Install ruby'
    rbenv install ${RUBYV} > /dev/null 2>&1
    rbenv global ${RUBYV} > /dev/null 2>&1
    symlink "${CLONE_PATH}/.rbenv/versions/${RUBYV}/bin/ruby" "${RUBY_PATH}"
    RUBY_V="$(ruby -v)"
    output_msg "${?}" 'ruby'
}

install_gem(){
    echoG 'Install gem'
    symlink "${CLONE_PATH}/.rbenv/versions/${RUBYV}/bin/gem" '/usr/bin/gem'
    GEM_V="$(gem -v)"
    output_msg "${?}" 'gem'
}

install_bundle(){
    echoG 'Install bundle'
    symlink "${CLONE_PATH}/.rbenv/versions/${RUBYV}/bin/bundle" '/usr/bin/bundle'
}

install_bundler(){
    echoG 'Install bundler'
    gem install bundler --no-document > /dev/null 2>&1
    symlink "${CLONE_PATH}/.rbenv/versions/${RUBYV}/bin/bundler" '/usr/bin/bundler'
    BUNDLER_V=$(bundler -v)
    output_msg "${?}" 'bundler'  
}

install_spring(){
    echoG 'Install spring'
    symlink "${CLONE_PATH}/.rbenv/versions/${RUBYV}/bin/spring" '/usr/bin/spring'
}

install_lsapi(){
    echoG '[Start] Install LSAPI'
    gem install rack --no-document >/dev/null 2>&1
    gem install ruby-lsapi --no-document >/dev/null 2>&1
    echoG '[End] Install LSAPI'  
}

install_rails(){
    echoG 'Install rails'
    gem install rails >/dev/null 2>&1
    symlink "${CLONE_PATH}/.rbenv/versions/${RUBYV}/bin/rails" '/usr/bin/rails'
    RAILS_V="$(rails -v)"
    output_msg "${?}" 'rails'   
}

centos_install_rbenv(){
    install_rbenv
}

centos_install_ruby(){
    install_ruby
}

centos_install_gem(){
    install_gem    
}

centos_install_bundler(){
    install_bundler 
}

centos_install_bundle(){
    install_bundle 
}

centos_install_spring(){
    install_spring
}

centos_install_lsapi(){
    install_lsapi
}

centos_install_rails(){
    install_rails 
}

ubuntu_install_rbenv(){
    install_rbenv
}

ubuntu_install_ruby(){
    install_ruby
}

ubuntu_install_gem(){
    install_gem    
}

ubuntu_install_bundler(){
    install_bundler        
}

ubuntu_install_bundle(){
    install_bundle 
}

ubuntu_install_spring(){
    install_spring
}

ubuntu_install_lsapi(){
    install_lsapi
}

ubuntu_install_rails(){
    install_rails   
}

centos_install_certbot(){
    echoG "[Start] Install CertBot"
    if [ ${OSVER} = 8 ]; then
        wget -q https://dl.eff.org/certbot-auto
        mv certbot-auto /usr/local/bin/certbot
        chown root /usr/local/bin/certbot
        chmod 0755 /usr/local/bin/certbot
        echo "y" | /usr/local/bin/certbot > /dev/null 2>&1
    else
        yum -y install certbot  > /dev/null 2>&1
    fi
    if [ -e /usr/bin/certbot ]; then 
        echoG '[End] Install CertBot'
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
  location                /usr/local/lsws/Example/html/demo/
  binPath                 /usr/bin/ruby
  appType                 rails

  rewrite  {

  }
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
    echoG '[Start] Install app'
    cd ${VHDOCROOT}; rails new ${PROJNAME} >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        echoG "${PROJNAME} project create success!"
    else
        echoR 'Something went wrong, please check!'
    fi
    echoG 'Generate Welcome'
    cd ${PROJNAME}; rails generate controller Welcome index >/dev/null 2>&1
    sleep 3
    grep welcome config/routes.rb >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        NEWKEY='  get "/", to: "rails/welcome#index"'
        linechange '/index' config/routes.rb "${NEWKEY}"
    else 
        echoR 'Welcome not exist! Skip setting'
    fi        
    echoG '[End] Install app'
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
    echoG '[Start] Install Firewall'
    if [ ! -e /usr/sbin/firewalld ]; then 
        yum -y install firewalld > /dev/null 2>&1
    fi
    service firewalld start > /dev/null 2>&1
    systemctl enable firewalld > /dev/null 2>&1
    echoG '[End] Install Firewall'
}

centos_config_firewall(){
    echoG '[Start] Setting Firewall'
    for PORT in ${FIREWALLLIST}; do 
        firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
    done 
    firewall-cmd --reload > /dev/null 2>&1
    firewall-cmd --list-all | grep 80 > /dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG '[End] Setting Firewall'
    else 
        echoR '[X] Please check firewalld rules'
    fi 
    if [ ${PROVIDER} = 'oracle' ]; then 
        oci_iptables
    fi
}

ubuntu_config_firewall(){
    echoG '[Start] Setting Firewall'
    #ufw status verbose | grep inactive > /dev/null 2>&1
    #if [ ${?} = 0 ]; then 
    for PORT in ${FIREWALLLIST}; do
        ufw allow ${PORT} > /dev/null 2>&1
    done    
    echo "y" | ufw enable > /dev/null 2>&1

    ufw status | grep '80.*ALLOW' > /dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG '[End] Setting Firewall'
    else 
        echoR '[X] Please check ufw rules'    
    fi 
    #else
    #    echoG "ufw already enabled"    
    #fi
    if [ ${PROVIDER} = 'oracle' ]; then 
        oci_iptables
    fi    
}

rm_dummy(){
    echoG '[Start] Remove dummy file'
    rm -f "${NOWPATH}/example.csr" "${NOWPATH}/privkey.pem"
    echoG '[End] Remove dummy file'
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
    centos_install_rbenv
    centos_install_ruby
    centos_install_gem
    centos_install_bundler
    centos_install_bundle
    centos_install_lsapi
    centos_install_rails
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
    ubuntu_install_rbenv
    ubuntu_install_ruby
    ubuntu_install_gem
    ubuntu_install_bundler
    ubuntu_install_bundle
    ubuntu_install_lsapi
    ubuntu_install_rails    
    ubuntu_install_certbot
}    

ubuntu_main_config(){
    ubuntu_set_app
    ubuntu_set_ols
    ubuntu_config_firewall
}

list_version(){
    echoG '=============Installed Versions============'
    printf "%-7s version: %-10s \n" 'NodeJS' "${NODE_V}"
    printf "%-7s version: %-10s \n" 'NPM'    "${NPM_V}"
    printf "%-7s version: %-10s \n" 'rbenv' "$(echo ${RBEN_V} | awk '{print $2}')"
    printf "%-7s version: %-10s \n" 'Ruby' "$(echo ${RUBY_V} | awk '{print $2}')"
    printf "%-7s version: %-10s \n" 'gem' "${GEM_V}"
    printf "%-7s version: %-10s \n" 'Bundler' "$(echo ${BUNDLER_V} | awk '{print $3}')"
    printf "%-7s version: %-10s \n" 'Rails' "$(echo ${RAILS_V} | awk '{print $2}')"
    echoG '==========================================='
}

end_message(){
    rm_dummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
    list_version
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
exit 0