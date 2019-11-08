#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed WordPress setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0.1
# *********************************************************************/
LSWSFD='/usr/local/lsws'
DOCHM='/var/www/html.old'
DOCLAND='/var/www/html'
PHPCONF='/var/www/phpmyadmin'
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
WPVHCONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
EXAMPLECONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
PHPINICONF="${LSWSFD}/lsphp73/etc/php/7.3/litespeed/php.ini"
MEMCACHECONF='/etc/memcached.conf'
REDISSERVICE='/lib/systemd/system/redis-server.service'
REDISCONF='/etc/redis/redis.conf'
WPCONSTCONF="${DOCHM}/wp-content/plugins/litespeed-cache/data/const.default.ini"
MARIADBCNF='/etc/mysql/mariadb.conf.d/60-server.cnf'
PHPVER=73
FIREWALLLIST="22 80 443"
USER='www-data'
GROUP='www-data'
THEME='twentynineteen'
PLUGINLIST="litespeed-cache.zip all-in-one-seo-pack.zip all-in-one-wp-migration.zip google-analytics-for-wordpress.zip jetpack.zip wp-mail-smtp.zip"
root_mysql_pass=$(openssl rand -hex 24)
ALLERRORS=0
EXISTSQLPASS=''
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

cksqlver(){
    SQLDBVER=$(/usr/bin/mysql -V)
}


### ENV
check_os()
{
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
        PHPINICONF="${LSWSFD}/lsphp73/etc/php.ini"
        MARIADBCNF='/etc/my.cnf.d/60-server.cnf'
        REDISSERVICE='/lib/systemd/system/redis.service'
        REDISCONF='/etc/redis.conf'
        MEMCACHESERVICE='/etc/systemd/system/memcached.service'
        MEMCACHECONF='/etc/sysconfig/memcached'
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
oshmpath()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
        HMPATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
        HMPATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'aliyun' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
    else
        HMPATH='/root'
    fi
}
oshmpath
DBPASSPATH="${HMPATH}/.db_password"


change_owner(){
  chown -R ${USER}:${GROUP} /var/www
}

install_basic_pkg(){
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install wget > /dev/null 2>&1
    else  
        apt-get -y install wget > /dev/null 2>&1
    fi
}

prepare(){
    mkdir -p "${DOCLAND}"
    change_owner
    install_basic_pkg
}

### Upgrade
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

### Start
install_olswp(){
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
}

conf_path(){
    if [ -f "${LSWSCONF}" ]; then 
        #WPVHCONF = /usr/local/lsws/conf/vhosts/wordpress/vhconf.conf   
        if [ ! -f $(grep 'configFile.*wordpress' "${LSWSCONF}" | awk '{print $2}') ]; then 
            WPVHCONF="${EXAMPLECONF}"
        fi
    else
        echo 'Can not find LSWS Config, exit script'
        exit 1    
    fi
}

install_pkg(){
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install unzip > /dev/null 2>&1
        echoG 'Install lsphp extensions'
        yum -y install lsphp${PHPVER}-memcached lsphp${PHPVER}-redis lsphp${PHPVER}-opcache lsphp${PHPVER}-imagick > /dev/null 2>&1
        echoG 'Install Memcached'
        yum -y install memcached > /dev/null 2>&1
        echoG 'Install Redis'
        yum -y install redis > /dev/null 2>&1
    else  
        apt-get -y install unzip > /dev/null 2>&1
        echoG 'Install lsphp extensions'
        apt-get -y install lsphp${PHPVER}-memcached lsphp${PHPVER}-redis lsphp${PHPVER}-opcache lsphp${PHPVER}-imagick > /dev/null 2>&1
        echoG 'Install Memcached'
        apt-get -y install memcached > /dev/null 2>&1
        echoG 'Install Redis'
        apt-get -y install redis > /dev/null 2>&1
        echoG 'Install Postfix'
        DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install postfix > /dev/null 2>&1
    fi
    ### Memcache
    systemctl start memcached > /dev/null 2>&1
    systemctl enable memcached > /dev/null 2>&1
    ### Redis
    systemctl start redis > /dev/null 2>&1 
    ### phpmyadmin
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
    if [ -e /usr/bin/certbot ] || [ -e /usr/local/bin/certbot ]; then 
        echoG 'Install CertBot finished'
    else 
        echoR 'Please check CertBot'    
    fi
    ### Mariadb 10.3
    cksqlver
    if [[ ${SQLDBVER} == *[10-99].[3-9]*-MariaDB* ]]; then
        echoG 'Mariadb version -ge 10.3'
    else
        if [ "${OSNAME}" = 'centos' ]; then
            echo "Mariadb version ${SQLDBVER} is lower than 10.3"
        else    
            echo "Mariadb version ${SQLDBVER} is lower than 10.3, upgrading"

            apt -y remove mariadb-server-* > /dev/null 2>&1
            echoG "Install Mariadb 10.3"
            DEBIAN_FRONTEND='noninteractive' apt-get -y \
                -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' \
                install mariadb-server-10.3 > /dev/null 2>&1
            cksqlver
            if [[ ${SQLDBVER} == *[10-99].[3-9]*-MariaDB* ]]; then
                echoG 'Mariadb version -ge 10.3'
            else
                echoR "Please check Mariadb $(/usr/bin/mysql -V)" 
            fi     
        fi     
    fi        
}

install_wp_cli(){
    ### WP CLI
    if [ -e /usr/local/bin/wp ]; then 
        echoG 'WP CLI already exist'
    else    
        echoG "Install wp_cli"
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi
}

config_ols(){
    echoG 'Setting Web Server config'
    ### Change user to www-data
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
        sed -i "s/nobody/${USER}/g" ${LSWSCONF}
        sed -i "s/nogroup/${GROUP}/g" ${LSWSCONF}
    fi    
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install --reinstall openlitespeed > /dev/null 2>&1
    else    
        apt-get -y install --reinstall openlitespeed > /dev/null 2>&1
    fi    
   ### Change wordpress virtualhost root to /var/www/html
    NEWKEY='  vhRoot                  /var/www/html'
    linechange 'www/html' ${LSWSCONF} "${NEWKEY}"
    ### change doc root to landing page, setup phpmyadmin context
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

config_php(){
    echoG 'Updating PHP Paremeter'
    NEWKEY='max_execution_time = 360'
    linechange 'max_execution_time' ${PHPINICONF} "${NEWKEY}"

    NEWKEY='post_max_size = 16M'
    linechange 'post_max_size' ${PHPINICONF} "${NEWKEY}"

    NEWKEY='upload_max_filesize = 16M'
    linechange 'upload_max_filesize' ${PHPINICONF} "${NEWKEY}"
    echoG 'Finish PHP Paremeter'
}

ubuntu_config_obj(){
   echoG 'Setting Object Cache'
    ### Memcached Unix Socket
    service memcached stop > /dev/null 2>&1
    cat >> "${MEMCACHECONF}" <<END 
-s /var/www/memcached.sock
-a 0770
-p /tmp/memcached.pid
END
    NEWKEY="-u ${USER}"
    linechange '\-u memcache' ${MEMCACHECONF} "${NEWKEY}"  
    systemctl daemon-reload > /dev/null 2>&1
    service memcached start > /dev/null 2>&1

    ### Redis Unix Socket
    service redis-server stop > /dev/null 2>&1
    NEWKEY="Group=${GROUP}"
    linechange 'Group=' ${REDISSERVICE} "${NEWKEY}"  
    cat >> "${REDISCONF}" <<END 
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 775
END
    systemctl daemon-reload > /dev/null 2>&1
    service redis-server start > /dev/null 2>&1
    echoG 'Finish Object Cache'
}

centos_config_obj(){
   echoG 'Setting Object Cache'
    ### Memcached Unix Socket
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
    systemctl daemon-reload > /dev/null 2>&1
    service memcached start > /dev/null 2>&1

    ### Redis Unix Socket
    service redis stop > /dev/null 2>&1
    NEWKEY="Group=${GROUP}"
    linechange 'Group=' ${REDISSERVICE} "${NEWKEY}"  
    cat >> "${REDISCONF}" <<END 
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 775
END
    systemctl daemon-reload > /dev/null 2>&1
    service redis start > /dev/null 2>&1
    echoG 'Finish Object Cache'
}

config_mysql(){
    echoG 'Setting DataBase'
    if [ -f ${DBPASSPATH} ]; then 
        EXISTSQLPASS=$(grep root_mysql_passs ${HMPATH}/.db_password | awk -F '"' '{print $2}'); 
    fi    
    if [ "${EXISTSQLPASS}" = '' ]; then
        mysql -u root -p${root_mysql_pass} \
            -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';"
    else
        mysql -u root -p${EXISTSQLPASS} \     
            -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';" 
    fi   
    if [ ! -e ${MARIADBCNF} ]; then 
    touch ${MARIADBCNF}
    cat > ${MARIADBCNF} <<END 
[mysqld]
sql_mode="NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER"
END
    fi
    echoG 'Finish DataBase'
}



config_wp(){
    echoG 'Setting WordPress'
### Install popular WP plugins
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

###  LSCACHE read DATA 
    cat << EOM > "${WPCONSTCONF}" 
; This is the default LSCWP configuration file
; All keys and values please refer const.cls.php
; Here just list some examples
; Comments start with \`;\`
; OPID_PURGE_ON_UPGRADE
purge_upgrade = true
; OPID_CACHE_PRIV
cache_priv = true
; OPID_CACHE_COMMENTER
cache_commenter = true
;Object_Cache_Enable
cache_object = true
; OPID_CACHE_OBJECT_HOST
;cache_object_host = 'localhost'
cache_object_host = '/var/www/memcached.sock'
; OPID_CACHE_OBJECT_PORT
;cache_object_port = '11211'
cache_object_port = ''
auto_upgrade = true


; OPID_CACHE_BROWSER_TTL
cache_browser_ttl = 2592000
; OPID_PUBLIC_TTL
public_ttl = 604800
; ------------------------------CDN Mapping Example BEGIN-------------------------------
; Need to add the section mark \`[litespeed-cache-cdn_mapping]\` before list
;
; NOTE 1) Need to set all child options to make all resources to be replaced without missing
; NOTE 2) \`url[n]\` option must have to enable the row setting of \`n\`
;
; To enable the 2nd mapping record by default, please remove the \`;;\` in the related lines
[litespeed-cache-cdn_mapping]
url[0] = ''
inc_js[0] = true
inc_css[0] = true
inc_img[0] = true
filetype[0] = '.aac
.css
.eot
.gif
.jpeg
.js
.jpg
.less
.mp3
.mp4
.ogg
.otf
.pdf
.png
.svg
.ttf
.woff'
;;url[1] = 'https://2nd_CDN_url.com/'
;;filetype[1] = '.webm'
; ------------------------------CDN Mapping Example END-------------------------------
EOM

    if [ ! -f ${DOCHM}/wp-content/themes/${THEME}/functions.php.bk ]; then 
        cp ${DOCHM}/wp-content/themes/${THEME}/functions.php ${DOCHM}/wp-content/themes/${THEME}/functions.php.bk
        cked
        ed ${DOCHM}/wp-content/themes/${THEME}/functions.php << END >>/dev/null 2>&1
19i
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
    echoG 'Finish WordPress'
    service lsws restart   
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

ubuntu_firewall_add(){
    echoG 'Setting Firewall'
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
    if [ $? = 0 ]; then 
        echoG 'firewalld rules setup success'
    else 
        echoR 'Please check firewalld rules'    
    fi         
}

status_ck(){
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

rm_dummy(){
    echoG 'Remove dummy file'
    rm -f "${NOWPATH}/example.csr" "${NOWPATH}/privkey.pem"
    echoG 'Finished dummy file'
}

### Main
main(){
    START_TIME="$(date -u +%s)"
    system_upgrade
    prepare
    install_olswp
    conf_path
    install_pkg
    install_wp_cli
    landing_pg
    config_ols
    config_php
    [[ ${OSNAME} = 'centos' ]] && centos_config_obj || ubuntu_config_obj 
    config_mysql
    config_wp
    db_password_file
    change_owner
    [[ ${OSNAME} = 'centos' ]] && centos_firewall_add || ubuntu_firewall_add
    status_ck
    rm_dummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}
main
#echoG 'Auto remove script itself'
#rm -- "$0"
exit 0