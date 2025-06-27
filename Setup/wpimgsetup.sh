#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed WordPress setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2024
# *********************************************************************/
LSWSFD='/usr/local/lsws'
DOCHM='/var/www/html.old'
DOCLAND='/var/www/html'
PHPCONF='/var/www/phpmyadmin'
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
WPVHCONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
EXAMPLECONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
MEMCACHECONF='/etc/memcached.conf'
REDISSERVICE='/lib/systemd/system/redis-server.service'
REDISCONF='/etc/redis/redis.conf'
WPCONSTCONF="${DOCHM}/wp-content/plugins/litespeed-cache/data/const.default.json"
MARIADBSERVICE='/lib/systemd/system/mariadb.service'
PHPVER=84
FIREWALLLIST="22 80 443"
USER='www-data'
GROUP='www-data'
THEME='twentytwenty'
PLUGINLIST="litespeed-cache.zip"
#PLUGINLIST="litespeed-cache.zip all-in-one-wp-migration.zip google-analytics-for-wordpress.zip jetpack.zip dologin.zip"
root_mysql_pass=$(openssl rand -hex 24)
ALLERRORS=0
EXISTSQLPASS=''
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
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

cked()
{
    if [ -f /bin/ed ]; then
        echoG "ed exist"
    else
        echoG "no ed, ready to install"
        if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then  
            apt-get install ed -y > /dev/null 2>&1
        elif [ "${OSNAME}" = 'centos' ]; then    
            yum install ed -y > /dev/null 2>&1
        fi    
    fi    
}

get_sql_ver(){
    SQLDBVER=$(/usr/bin/mariadb -V | awk '{match($0,"([^ ]+)-MariaDB",a)}END{print a[1]}')
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
        REDISSERVICE='/lib/systemd/system/redis.service'
        REDISCONF='/etc/redis.conf'
        MEMCACHESERVICE='/etc/systemd/system/memcached.service'
        MEMCACHECONF='/etc/sysconfig/memcached'
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        OSNAMEVER="UBUNTU$(lsb_release -sr | awk -F '.' '{print $1}')"
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}

providerck()
{
    if  [ ${OSNAME} = 'centos' ] && [ ! -e /usr/sbin/dmidecode ]; then
        yum install -y dmidecode > /dev/null 2>&1
    fi
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

compatible_mariadb_cmd()
{
    if [ -e /usr/bin/mariadb ]; then
        mysqladmin='mariadb-admin'
        mysql='mariadb'
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
    --dbname wordpress \
    --dbuser wordpress \
    --dbpassword wordpress
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

centos_install_memcached(){
    echoG 'Install Memcached'
    yum -y install memcached > /dev/null 2>&1
    systemctl start memcached > /dev/null 2>&1
    systemctl enable memcached > /dev/null 2>&1
}

centos_install_redis(){
    echoG 'Install Redis'
    yum -y install redis > /dev/null 2>&1
    systemctl start redis > /dev/null 2>&1
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

ubuntu_install_memcached(){
    echoG 'Install Memcached'
    apt-get -y install memcached > /dev/null 2>&1
    systemctl start memcached > /dev/null 2>&1
    systemctl enable memcached > /dev/null 2>&1        
}

ubuntu_install_redis(){    
    echoG 'Install Redis'
    apt-get -y install redis > /dev/null 2>&1
    systemctl start redis > /dev/null 2>&1
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

install_wp_cli(){
    if [ -e /usr/local/bin/wp ]; then 
        echoG 'WP CLI already exist'
    else    
        echoG "Install wp_cli"
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi
    if [ ! -f /usr/bin/php ]; then
        ln -s ${LSWSFD}/lsphp${PHPVER}/bin/php /usr/bin/php
    fi
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

  phpIniOverride  {

  }
}

rewrite  {
  enable                1
  autoLoadHtaccess        1
}
END
    echoG 'Finish Web Server config'
}


landing_pg(){
    echoG 'Setting Landing Page'
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Static/wp-landing.html \
    -o ${DOCLAND}/index.html
    if [ -e ${DOCLAND}/index.html ]; then 
        echoG 'Landing Page finished'
    else
        echoR "Please check Landing Page here ${DOCLAND}/index.html"
    fi    
}

update_final_permission(){
    change_owner ${DOCHM}
    change_owner /tmp/lshttpd/lsphp.sock*
    rm -f /tmp/lshttpd/.rtreport 
    rm -f /tmp/lshttpd/.status
}

ubuntu_config_memcached(){
   echoG 'Setting Object Cache'
    service memcached stop > /dev/null 2>&1
    cat >> "${MEMCACHECONF}" <<END 
-s /var/www/memcached.sock
-a 0770
-P /tmp/memcached.pid
END
    NEWKEY="-u ${USER}"
    linechange '\-u memcache' ${MEMCACHECONF} "${NEWKEY}"  
    systemctl daemon-reload > /dev/null 2>&1
    service memcached start > /dev/null 2>&1
}

ubuntu_config_redis(){
    service redis-server stop > /dev/null 2>&1
    NEWKEY="Group=${GROUP}"
    linechange 'Group=' ${REDISSERVICE} "${NEWKEY}" 
    cat >> "${REDISCONF}" <<END 
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 775
END
    BIND_LINE=$(grep -n -m 1 '^bind 127' ${REDISCONF} | awk -F ':' '{print $1}')
    sed -i -e "${BIND_LINE}s/-::1// ; ${BIND_LINE}s/::1//" ${REDISCONF}
    systemctl daemon-reload > /dev/null 2>&1
    service redis-server start > /dev/null 2>&1
    echoG 'Finish Object Cache'
}

centos_config_memcached(){
    echoG 'Setting Object Cache'
    service memcached stop > /dev/null 2>&1 
    cat >> "${MEMCACHESERVICE}" <<END 
[Unit]
Description=Memcached
Before=httpd.service
After=network.target

[Service]
User=${USER}
Group=${GROUP}
Type=simple
EnvironmentFile=-/etc/sysconfig/memcached
ExecStart=/usr/bin/memcached -u \$USER -p \$PORT -m \$CACHESIZE -c \$MAXCONN \$OPTIONS

[Install]
WantedBy=multi-user.target
END
        cat > "${MEMCACHECONF}" <<END 
PORT="11211"
USER="${USER}"
MAXCONN="1024"
CACHESIZE="64"
OPTIONS="-s /var/www/memcached.sock -a 0770 -U 0 -l 127.0.0.1"
END
    ### SELINUX permissive Mode
    if [ ! -f /usr/sbin/semanage ]; then 
        yum install -y policycoreutils-python-utils > /dev/null 2>&1
    fi    
    semanage permissive -a memcached_t
    setsebool -P httpd_can_network_memcache 1
    systemctl daemon-reload > /dev/null
    service memcached start > /dev/null
}

centos_config_redis(){
    service redis stop > /dev/null 2>&1
    NEWKEY="Group=${GROUP}"
    linechange 'Group=' ${REDISSERVICE} "${NEWKEY}"  
    cat >> "${REDISCONF}" <<END 
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 775
END
    BIND_LINE=$(grep -n -m 1 '^bind 127' ${REDISCONF} | awk -F ':' '{print $1}')
    sed -i "${BIND_LINE}s/::1//" ${REDISCONF}
    systemctl daemon-reload > /dev/null
    service redis start > /dev/null
    echoG 'Finish Object Cache'
}

config_mysql(){
    echoG 'Setting DataBase'
    get_sql_ver
    if [ -f ${DBPASSPATH} ]; then 
        EXISTSQLPASS=$(grep root_mysql_passs ${HMPATH}/.db_password | awk -F '"' '{print $2}'); 
    fi    
    if [ "${EXISTSQLPASS}" = '' ]; then
        if (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=4 )); then
            "${mysql}" -u root -p${root_mysql_pass} \
                -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${root_mysql_pass}');"
        else
            "${mysql}" -u root -p${root_mysql_pass} \
                -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';"
        fi    
    else
        if (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=4)); then
            "${mysql}" -u root -p${EXISTSQLPASS} \
                -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${root_mysql_pass}');"
        else        
            "${mysql}" -u root -p${EXISTSQLPASS} \     
                -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';" 
        fi        
    fi
    #if [ -e ${MARIADBSERVICE} ]; then
    #    grep -i LogLevelMax ${MARIADBSERVICE} >/dev/null 2>&1
    #    if [ ${?} = 1 ]; then
    #        echo 'LogLevelMax=1' >> ${MARIADBSERVICE}
    #    fi
    #fi
    #if [ ! -e ${MARIADBCNF} ]; then 
    #touch ${MARIADBCNF}
    #cat > ${MARIADBCNF} <<END 
#[mysqld]
#sql_mode="NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER"
#END
 #   fi
    systemctl daemon-reload > /dev/null 2>&1
    systemctl restart mariadb > /dev/null
    echoG 'Finish DataBase'
}

install_wp_plugin(){
    echoG 'Setting WordPress'
    for PLUGIN in ${PLUGINLIST}; do
        echoG "Install ${PLUGIN}"
        wget -q -P ${DOCHM}/wp-content/plugins/ https://downloads.wordpress.org/plugin/${PLUGIN}
        if [ $? = 0 ]; then
            unzip -qq -o ${DOCHM}/wp-content/plugins/${PLUGIN} -d ${DOCHM}/wp-content/plugins/
        else
            echoR "${PLUGINLIST} FAILED to download"
        fi
    done
    rm -f ${DOCHM}/wp-content/plugins/*.zip
}

set_htaccess(){
    if [ ! -f ${DOCHM}/.htaccess ]; then 
        touch ${DOCHM}/.htaccess
    fi   
    cat << EOM > ${DOCHM}/.htaccess
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>

# END WordPress
EOM
}

get_theme_name(){
    THEME_NAME=$(grep WP_DEFAULT_THEME ${DOCHM}/wp-includes/default-constants.php | grep -v '!' | awk -F "'" '{print $4}')
    echo "${THEME_NAME}" | grep 'twenty' >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        THEME="${THEME_NAME}"
    fi
}

set_lscache(){ 
    wget -q -O ${WPCONSTCONF} https://raw.githubusercontent.com/litespeedtech/lscache_wp/refs/heads/master/data/const.default.json
    if [ -f ${WPCONSTCONF} ]; then
        sed -ie 's/"object": .*"/"object": '\"true\"'/g' ${WPCONSTCONF}
        sed -ie 's/"object-host": .*"/"object-host": '\"\\/var\\/www\\/memcached.sock\"'/g' ${WPCONSTCONF}
        sed -ie 's/"object-port": .*"/"object-port": '\"\"'/g' ${WPCONSTCONF}
    fi
    THEME_PATH="${DOCHM}/wp-content/themes/${THEME}"
    if [ ! -f ${THEME_PATH}/functions.php ]; then
        cat >> "${THEME_PATH}/functions.php" <<END
<?php
require_once( WP_CONTENT_DIR.'/../wp-admin/includes/plugin.php' );
\$path = 'litespeed-cache/litespeed-cache.php' ;
if (!is_plugin_active( \$path )) {
    activate_plugin( \$path ) ;
    rename( __FILE__ . '.bk', __FILE__ );
}
END
        if [ ! -f ${THEME_PATH}/functions.php.bk ]; then
            cat >> "${THEME_PATH}/functions.php.bk" <<END
<?php 
END
        fi
    elif [ ! -f ${THEME_PATH}/functions.php.bk ]; then 
        cp ${THEME_PATH}/functions.php ${THEME_PATH}/functions.php.bk
        cked
        ed ${THEME_PATH}/functions.php << END >>/dev/null 2>&1
2i
require_once( WP_CONTENT_DIR.'/../wp-admin/includes/plugin.php' );
\$path = 'litespeed-cache/litespeed-cache.php' ;
if (!is_plugin_active( \$path )) {
    activate_plugin( \$path ) ;
    rename( __FILE__ . '.bk', __FILE__ );
}
.
w
q
END
    fi
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
    for ITEM in lsws memcached redis-server mariadb
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
    for ITEM in lsws memcached redis mariadb
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
    centos_install_memcached
    centos_install_redis
    centos_install_certbot
    install_phpmyadmin
    install_wp_cli
    landing_pg
}

centos_main_config(){
    centos_config_ols
    centos_config_memcached
    centos_config_redis
    wp_main_config
}

ubuntu_main_install(){
    ubuntu_install_basic
    ubuntu_install_ols
    ubuntu_install_memcached
    ubuntu_install_redis
    ubuntu_install_certbot
    install_phpmyadmin
    install_wp_cli
    landing_pg
}

ubuntu_main_config(){
    ubuntu_config_ols
    ubuntu_config_memcached
    ubuntu_config_redis   
    wp_main_config 
}

wp_config(){
    install_wp_plugin
    set_htaccess
    get_theme_name
    set_lscache
}

wp_main_config(){
    compatible_mariadb_cmd
    config_mysql
    wp_config
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
