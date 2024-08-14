#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed WordPress setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# *********************************************************************/
LSWSFD='/usr/local/lsws'
DOCHM='/var/www/html.old'
DOCLAND='/var/www/html'
PHPCONF='/var/www/phpmyadmin'
LSWSVCONF="${LSWSFD}/conf/vhosts"
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
WPVHCONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
EXAMPLECONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
PHPVERD=8.3
PHPVER=$(echo ${PHPVERD//./})
PHP_MV=$(cut -d "." -f1 <<< ${PHPVER})
PHP_SV=$(cut -d "." -f2 <<< ${PHPVER})
PHPINICONF="${LSWSFD}/lsphp${PHPVER}/etc/php/${PHPVERD}/litespeed/php.ini"
MARIADBSERVICE='/lib/systemd/system/mariadb.service'
MARIADBCNF='/etc/mysql/mariadb.conf.d/60-server.cnf'
DRUSHVER=12
FIREWALLLIST="22 80 443"
USER='www-data'
GROUP='www-data'
root_mysql_pass=$(openssl rand -hex 24)
ALLERRORS=0
EXISTSQLPASS=''
NOWPATH=$(pwd)
BOTCRON='/etc/cron.d/certbot'

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

get_sql_ver(){
    SQLDBVER=$(/usr/bin/mysql -V | awk '{match($0,"([^ ]+)-MariaDB",a)}END{print a[1]}')
    SQL_MAINV=$(echo ${SQLDBVER} | awk -F '.' '{print $1}')
    SQL_SECV=$(echo ${SQLDBVER} | awk -F '.' '{print $2}')
}

check_sql_ver(){    
    if (( ${SQL_MAINV} >=11 && ${SQL_MAINV}<=99 )); then
        echoG '[OK] Mariadb version -ge 11'
    elif (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=3 )); then
        echoG '[OK] Mariadb version -ge 10.3'
    else
        echoR "Mariadb version ${SQLDBVER} is lower than 10.3, please check!"    
    fi     
}


check_os()
{
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
        PHPINICONF="${LSWSFD}/lsphp${PHPVER}/etc/php.ini"
        MARIADBCNF='/etc/my.cnf.d/60-server.cnf'
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
        BOTCRON='/etc/crontab'
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        OSNAMEVER="UBUNTU$(lsb_release -sr | awk -F '.' '{print $1}')"    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
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

oshmpath()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
        HMPATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
        HMPATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'aliyun' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'oracle' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'        
    else
        HMPATH='/root'
    fi
    DBPASSPATH="${HMPATH}/.db_password"
}

change_owner(){
  chown -R ${USER}:${GROUP} ${1}
}

prepare(){
    mkdir -p "${DOCLAND}"
    change_owner /var/www
}

system_upgrade() {
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

wp_conf_path(){
    if [ -f "${LSWSCONF}" ]; then 
        if [ ! -f $(grep 'configFile.*wordpress' "${LSWSCONF}" | awk '{print $2}') ]; then 
            WPVHCONF="${EXAMPLECONF}"
        fi
    else
        echo 'Can not find LSWS Config, exit script'
        exit 1    
    fi
}

rm_dummy(){
    echoG 'Remove dummy file'
    rm -f "/tmp/example.csr" "/tmp/privkey.pem"
}

install_ols_wp(){
    cd /tmp/; wget -q https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh
    chmod +x ols1clk.sh
    echo 'Y' | bash ols1clk.sh \
    --lsphp ${PHPVER} \
    --wordpress \
    --wordpresspath ${DOCHM} \
    --dbrootpassword ${root_mysql_pass} \
    --dbname drupal \
    --dbuser drupal \
    --dbpassword drupal
    rm -f ols1clk.sh
    wp_conf_path
    rm_dummy
}

restart_lsws(){
    echoG 'Restart LiteSpeed Web Server'
    ${LSWSFD}/bin/lswsctrl stop >/dev/null 2>&1
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws >/dev/null 2>&1
}

centos_install_basic(){
    yum -y install wget unzip > /dev/null 2>&1
}

centos_install_ols(){
    install_ols_wp
}

centos_install_php(){
    echoG 'Install lsphp extensions'
    yum -y install lsphp${PHPVER}-opcache > /dev/null 2>&1
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

ubuntu_install_basic(){
    apt-get -y install wget unzip ufw > /dev/null 2>&1
}

ubuntu_install_ols(){
    install_ols_wp
}

ubuntu_install_php(){
    echoG 'Install lsphp extensions'
    apt-get -y install lsphp${PHPVER}-opcache > /dev/null 2>&1
}

ubuntu_install_postfix(){
    echoG 'Install Postfix'
    DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold' install postfix > /dev/null 2>&1
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

install_composer(){
    echoG 'Install composer'
    curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
    HASH=`curl -sS https://composer.github.io/installer.sig`
    php -r "if (hash_file('SHA384', '/tmp/composer-setup.php') === '$HASH'){ echo 'Installer verified'; } 
        else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" >/dev/null
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer >/dev/null
    if [ -e /usr/local/bin/composer ]; then 
        export COMPOSER_ALLOW_SUPERUSER=1
    else
        echoR 'Composer install failed, exit!'; exit 1
    fi    
    if [ ! -e /usr/bin/composer ]; then 
        ln -s /usr/local/bin/composer /usr/bin/composer
    fi    
}

install_drush(){
    echoG 'Install Drush'
    composer global require drush/drush:^${DRUSHVER} --with-all-dependencies -W -q
    wget -O drush.phar https://github.com/drush-ops/drush-launcher/releases/latest/download/drush.phar -q
    chmod +x drush.phar
    if [ ! -e /usr/local/bin/drush ]; then 
        mv drush.phar /usr/local/bin/drush
    fi
    if [ ! -e /usr/bin/drush ]; then 
        ln -s /usr/local/bin/drush /usr/bin/drush
    fi
}    

install_phpmyadmin(){
    if [ ! -f ${PHPCONF}/changelog.php ]; then 
        cd /tmp/ 
        echoG 'Download phpmyadmin'
        wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
        unzip phpMyAdmin-latest-all-languages.zip > /dev/null 2>&1
        rm -f phpMyAdmin-latest-all-languages.zip
        echoG "move phpmyadmin to ${PHPCONF}"
        mv phpMyAdmin-*-all-languages ${PHPCONF}
        mv ${PHPCONF}/config.sample.inc.php ${PHPCONF}/config.inc.php
    fi
    change_owner ${PHPCONF}
}  

centos_config_ols(){
    echoG 'Setting Web Server config'
    yum -y install --reinstall openlitespeed > /dev/null 2>&1   
    NEWKEY='  vhRoot                  /var/www/html'
    linechange 'www/html' ${LSWSCONF} "${NEWKEY}"
    sed -i '/errorlog logs\/error.log/a \ \ \ \ \ \ \ \ keepDays             1' ${LSWSCONF}
    sed -i 's/maxStaleAge         200/maxStaleAge         0/g' ${LSWSCONF}
    cat > ${WPVHCONF} <<END 
docRoot                   ${DOCLAND}/

index  {
  useServer               0
  indexFiles              index.php index.html
}

context /phpmyadmin/ {
  location                ${PHPCONF}/
  allowBrowse             1
  indexFiles              index.php

  accessControl  {
    allow                 *
  }

  rewrite  {
    enable                0
    inherit               0

  }
  addDefaultCharset       off

  phpIniOverride  {

  }
}

rewrite  {
  enable                1
  autoLoadHtaccess        1
}
END
    if [ -d ${LSWSVCONF}/wordpress ] && [ ! -d ${LSWSVCONF}/drupal ]; then 
        mv ${LSWSVCONF}/wordpress ${LSWSVCONF}/drupal  
    fi
    sed -i "s/wordpress/drupal/g" ${LSWSCONF}
    echoG 'Finish Web Server config'
}

ubuntu_config_ols(){
    echoG 'Setting Web Server config'
    sed -i "s/nobody/${USER}/g" ${LSWSCONF}
    sed -i "s/nogroup/${GROUP}/g" ${LSWSCONF}
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confdef' \
        -o Dpkg::Options::='--force-confold' -y install --reinstall openlitespeed > /dev/null 2>&1
    NEWKEY='  vhRoot                  /var/www/html'
    linechange 'www/html' ${LSWSCONF} "${NEWKEY}"
    sed -i '/errorlog logs\/error.log/a \ \ \ \ \ \ \ \ keepDays             1' ${LSWSCONF}
    sed -i 's/maxStaleAge         200/maxStaleAge         0/g' ${LSWSCONF}
    cat > ${WPVHCONF} <<END 
docRoot                   ${DOCLAND}/

index  {
  useServer               0
  indexFiles              index.php index.html
}

context /phpmyadmin/ {
  location                ${PHPCONF}
  allowBrowse             1
  indexFiles              index.php

  accessControl  {
    allow                 *
  }

  rewrite  {
    enable                0
    inherit               0

  }
  addDefaultCharset       off

}

rewrite  {
  enable                1
  autoLoadHtaccess        1
}
END
    if [ -d ${LSWSVCONF}/wordpress ] && [ ! -d ${LSWSVCONF}/drupal ]; then 
        mv ${LSWSVCONF}/wordpress ${LSWSVCONF}/drupal  
    fi
    sed -i "s/wordpress/drupal/g" ${LSWSCONF}
    echoG 'Finish Web Server config'
}


landing_pg(){
    echoG 'Setting Landing Page'
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Static/drupal-landing.html \
    -o ${DOCLAND}/index.html
    if [ -e ${DOCLAND}/index.html ]; then 
        echoG 'Landing Page finished'
    else
        echoR "Please check Landing Page here ${DOCLAND}/index.html"
    fi    
}

config_php(){
    echoG 'Updating PHP Paremeter'
    NEWKEY='max_execution_time = 360'
    linechange 'max_execution_time' ${PHPINICONF} "${NEWKEY}"
    NEWKEY='post_max_size = 64M'
    linechange 'post_max_size' ${PHPINICONF} "${NEWKEY}"
    NEWKEY='upload_max_filesize = 64M'
    linechange 'upload_max_filesize' ${PHPINICONF} "${NEWKEY}"
    echoG 'Finish PHP Paremeter'
}

update_final_permission(){
    change_owner ${DOCHM}
    change_owner /tmp/lshttpd/lsphp.sock*
    rm -f /tmp/lshttpd/.rtreport 
    rm -f /tmp/lshttpd/.status
}

config_mysql(){
    echoG 'Setting DataBase'
    get_sql_ver
    if [ -f ${DBPASSPATH} ]; then 
        EXISTSQLPASS=$(grep root_mysql_passs ${HMPATH}/.db_password | awk -F '"' '{print $2}'); 
    fi    
    if [ "${EXISTSQLPASS}" = '' ]; then
        if (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=4 )); then
            mysql -u root -p${root_mysql_pass} \
                -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${root_mysql_pass}');"
        else
            mysql -u root -p${root_mysql_pass} \
                -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';"
        fi    
    else
        if (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=4)); then
            mysql -u root -p${EXISTSQLPASS} \
                -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${root_mysql_pass}');"
        else        
            mysql -u root -p${EXISTSQLPASS} \     
                -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';" 
        fi        
    fi
    if [ ! -e ${MARIADBCNF} ]; then 
    touch ${MARIADBCNF}
    cat > ${MARIADBCNF} <<END 
[mysqld]
sql_mode="NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER"
END
    fi
    systemctl daemon-reload > /dev/null 2>&1
    systemctl restart mariadb > /dev/null
    echoG 'Finish DataBase'
}

db_password_file(){
    echoG 'Create db fiile'
    if [ -f ${DBPASSPATH} ]; then 
        echoY "${DBPASSPATH} already exist!, will recreate a new file"
        rm -f ${DBPASSPATH}
    fi    
    touch "${DBPASSPATH}"
    cat >> "${DBPASSPATH}" <<EOM
root_mysql_pass="${root_mysql_pass}"
EOM
    echoG 'Finish db fiile'
}

app_drupal_dl(){
    echoG 'Download Drupal CMS'
    if [ ! -d "${DOCHM}/sites" ]; then
        composer create-project --no-interaction drupal/recommended-project ${DOCHM} >/dev/null 2>&1
        cd ${DOCHM} && composer require drush/drush -q
    else
        echo 'Drupal already exist, abort!'
        exit 1
    fi
}

cache_plugin_dl(){
    echoG 'Download Cache Plugin'
    if [ -d "${DOCHM}/web/modules" ] && [ ! -d "${DOCHM}/web/modules/lscache-drupal-master" ]; then 
        cd ${DOCHM}/web/modules
        wget https://github.com/litespeedtech/lscache-drupal/archive/master.zip -O master.zip -q 
        unzip -qq master.zip
        rm -f master.zip
    else
        echo 'Skip cache plugin download!'    
    fi
}


rm_wordpress(){
    echoG 'Remove doc root'
    rm -rf ${DOCHM}
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

ubuntu_firewall_add(){
    echoG 'Setting Firewall'
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
    if [ ${PROVIDER} = 'oracle' ]; then 
        oci_iptables
    fi
}

centos_firewall_add(){
    echoG 'Setting Firewall'
    if [ ! -e /usr/sbin/firewalld ]; then 
        yum -y install firewalld > /dev/null 2>&1
    fi
    service firewalld start  > /dev/null 2>&1
    systemctl enable firewalld > /dev/null 2>&1
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

ubuntu_service_check(){
    check_sql_ver
    for ITEM in lsws mariadb
    do 
        service ${ITEM} status | grep "active\|running" > /dev/null 2>&1
        if [ $? = 0 ]; then 
            echoG "Process ${ITEM} is active"
        else
            echoR "Please check Process ${ITEM}" 
            ALLERRORS=1
        fi
    done        
    if [[ "${ALLERRORS}" = 0 ]]; then 
        echoG "Congratulations! Installation finished."
    else
        echoR "Some errors seem to have occured, please check this as you may need to manually fix them"
    fi        
}

centos_service_check(){
    check_sql_ver
    for ITEM in lsws mariadb
    do 
        service ${ITEM} status | grep "active\|running" > /dev/null 2>&1
        if [ $? = 0 ]; then 
            echoG "Process ${ITEM} is active"
        else
            echoR "Please check Process ${ITEM}" 
            ALLERRORS=1
        fi
    done        
    if [[ "${ALLERRORS}" = 0 ]]; then 
        echoG "Congratulations! Installation finished."
    else
        echoR "Some errors seem to have occured, please check this as you may need to manually fix them"
    fi        
}

init_check(){
    START_TIME="$(date -u +%s)"
    check_os
    providerck
    oshmpath
}

init_setup(){
    system_upgrade
    prepare
}   

centos_main_install(){
    centos_install_basic
    centos_install_ols
    centos_install_php
    centos_install_certbot
    install_composer
    install_drush
    install_phpmyadmin
    landing_pg
}

centos_main_config(){
    centos_config_ols
    config_php
    app_main_config
}

ubuntu_main_install(){
    ubuntu_install_basic
    ubuntu_install_ols
    ubuntu_install_php
    ubuntu_install_certbot
    ubuntu_install_postfix
    install_composer
    install_drush
    install_phpmyadmin
    landing_pg
}

ubuntu_main_config(){
    ubuntu_config_ols
    config_php 
    app_main_config 
}

app_main_config(){
    config_mysql
    rm_wordpress
    app_drupal_dl
    cache_plugin_dl
    db_password_file
    update_final_permission
    restart_lsws
}

end_message(){
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}

main(){
    init_check
    init_setup
    if [ ${OSNAME} = 'centos' ]; then
        centos_main_install
        centos_main_config
        centos_firewall_add
        centos_service_check
    else
        ubuntu_main_install
        ubuntu_main_config
        ubuntu_firewall_add
        ubuntu_service_check
    fi
    end_message
}
main
exit 0