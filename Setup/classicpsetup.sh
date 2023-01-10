#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed ClassicPress setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2020-2021
# @Version: 1.0.0
# *********************************************************************/
LSWSFD='/usr/local/lsws'
DOCHM='/var/www/html.old'
DOCLAND='/var/www/html'
PHPCONF='/var/www/phpmyadmin'
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
WPVHCONF="${LSWSFD}/conf/vhosts/classicpress/vhconf.conf"
EXAMPLECONF="${LSWSFD}/conf/vhosts/classicpress/vhconf.conf"
PHPINICONF="${LSWSFD}/lsphp81/etc/php/8.1/litespeed/php.ini"
MEMCACHECONF='/etc/memcached.conf'
REDISSERVICE='/lib/systemd/system/redis-server.service'
REDISCONF='/etc/redis/redis.conf'
WPCONSTCONF="${DOCHM}/wp-content/plugins/litespeed-cache/data/const.default.ini"
MARIADBSERVICE='/lib/systemd/system/mariadb.service'
MARIADBCNF='/etc/mysql/mariadb.conf.d/60-server.cnf'
PHPVER=81
FIREWALLLIST="22 80 443"
USER='www-data'
GROUP='www-data'
THEME='classicpress-twentyseventeen'
PLUGINLIST="litespeed-cache.zip"
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
    SQLDBVER=$(/usr/bin/mysql -V | awk '{match($0,"([^ ]+)-MariaDB",a)}END{print a[1]}')
    SQL_MAINV=$(echo ${SQLDBVER} | awk -F '.' '{print $1}')
    SQL_SECV=$(echo ${SQLDBVER} | awk -F '.' '{print $2}')
}

check_sql_ver(){    
    if (( ${SQL_MAINV} >=11 && ${SQL_MAINV}<=99 )); then
        echoG '[OK] Mariadb version -ge 11'
    elif (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=3 && ${SQL_SECV}<=9 )); then
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
        PHPINICONF="${LSWSFD}/lsphp73/etc/php.ini"
        MARIADBCNF='/etc/my.cnf.d/60-server.cnf'
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
    #cd /tmp/; wget -q https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh
    cd /tmp/; wget -q https://raw.githubusercontent.com/litespeedtech/ols1clk/classicpress/ols1clk.sh
    chmod +x ols1clk.sh
    echo 'Y' | bash ols1clk.sh \
    --lsphp ${PHPVER} \
    --classicpress \
    --classicpresspath ${DOCHM} \
    --dbrootpassword ${root_mysql_pass} \
    --dbname classicpress \
    --dbuser classicpress \
    --dbpassword classicpress
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
    yum -y install lsphp${PHPVER}-memcached lsphp${PHPVER}-redis lsphp${PHPVER}-opcache lsphp${PHPVER}-imagick > /dev/null 2>&1
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
    apt-get -y install wget unzip > /dev/null 2>&1
}

ubuntu_install_ols(){
    install_ols_wp
}

ubuntu_install_php(){
    echoG 'Install lsphp extensions'
    apt-get -y install lsphp${PHPVER}-memcached lsphp${PHPVER}-redis lsphp${PHPVER}-opcache lsphp${PHPVER}-imagick > /dev/null 2>&1
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
    apt-get -y install --reinstall openlitespeed > /dev/null 2>&1
    
    NEWKEY='  vhRoot                  /var/www/html'
    linechange 'www/html' ${LSWSCONF} "${NEWKEY}"
    sed -i '/errorlog logs\/error.log/a \ \ \ \ \ \ \ \ keepDays             1' ${LSWSCONF}
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
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Static/cp-landing.html \
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

update_final_permission(){
    change_owner ${DOCHM}
    change_owner /tmp/lshttpd/lsphp.sock*
    rm -f /tmp/lshttpd/.rtreport 
    rm -f /tmp/lshttpd/.status
}

ubuntu_config_memcached(){
    echoG 'Setting Object Cache'
    chown ${USER}:${GROUP} /var/www
    service memcached stop > /dev/null 2>&1
    cat >> "${MEMCACHECONF}" <<END 
-s /var/www/memcached.sock
-a 0770
-p /tmp/memcached.pid
END
    NEWKEY="-u ${USER}"
    linechange '\-u memcache' ${MEMCACHECONF} "${NEWKEY}"  
    systemctl daemon-reload > /dev/null
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
    sed -i "${BIND_LINE}s/::1//" ${REDISCONF}
    systemctl daemon-reload > /dev/null
    service redis-server start > /dev/null 2>&1
    echoG 'Finish Object Cache'
}

centos_config_memcached(){
    echoG 'Setting Object Cache'
    chown ${USER}:${GROUP} /var/www
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
    service memcached start > /dev/null 2>&1
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
    systemctl daemon-reload > /dev/null 2>&1
    service redis start > /dev/null 2>&1
    echoG 'Finish Object Cache'
}

config_mysql(){
    echoG 'Setting DataBase'
    get_sql_ver
    if [ -f ${DBPASSPATH} ]; then 
        EXISTSQLPASS=$(grep root_mysql_passs ${HMPATH}/.db_password | awk -F '"' '{print $2}'); 
    fi    
    if [ "${EXISTSQLPASS}" = '' ]; then
        if (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=4 && ${SQL_SECV}<=9 )); then
            mysql -u root -p${root_mysql_pass} \
                -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${root_mysql_pass}');"
        else
            mysql -u root -p${root_mysql_pass} \
                -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';"
        fi    
    else
        if (( ${SQL_MAINV} >=10 )) && (( ${SQL_SECV} >=4 && ${SQL_SECV}<=9 )); then
            mysql -u root -p${EXISTSQLPASS} \
                -e "ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${root_mysql_pass}');"
        else        
            mysql -u root -p${EXISTSQLPASS} \     
                -e "update mysql.user set authentication_string=password('${root_mysql_pass}') where user='root';" 
        fi        
    fi
    if [ -e ${MARIADBSERVICE} ]; then
        grep -i LogLevelMax ${MARIADBSERVICE} >/dev/null 2>&1
        if [ ${?} = 1 ]; then
            echo 'LogLevelMax=1' >> ${MARIADBSERVICE}
        fi
    fi
    if [ ! -e ${MARIADBCNF} ]; then 
    touch ${MARIADBCNF}
    cat > ${MARIADBCNF} <<END 
[mysqld]
sql_mode="NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER"
END
    fi
    systemctl daemon-reload > /dev/null
    systemctl restart mariadb > /dev/null
    echoG 'Finish DataBase'
}

install_wp_plugin(){
    echoG 'Setting ClassicPress'
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
# BEGIN ClassicPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>

# END ClassicPress
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
    cat << EOM > "${WPCONSTCONF}" 
;
; This is the predefined default LSCWP configuration file
;
; All the keys and values please refer \`src/const.cls.php\`
;
; Comments start with \`;\`
;

;; -------------------------------------------------- ;;
;; --------------          General              ----------------- ;;
;; -------------------------------------------------- ;;

; O_AUTO_UPGRADE
auto_upgrade = true

; O_API_KEY
api_key = ''

; O_SERVER_IP
server_ip = ''

; O_NEWS
news = false


;; -------------------------------------------------- ;;
;; --------------               Cache           ----------------- ;;
;; -------------------------------------------------- ;;

cache-priv = true

cache-commenter = true

cache-rest = true

cache-page_login = true

cache-favicon = true

cache-resources = true

cache-browser = false

cache-mobile = false

cache-mobile_rules = 'Mobile
Android
Silk/
Kindle
BlackBerry
Opera Mini
Opera Mobi'

cache-exc_useragents = ''

cache-exc_cookies = ''

cache-exc_qs = ''

cache-exc_cat = ''

cache-exc_tag = ''

cache-force_uri = ''

cache-force_pub_uri = ''

cache-priv_uri = ''

cache-exc = ''

cache-exc_roles = ''

cache-drop_qs = 'fbclid
gclid
utm*
_ga'

cache-ttl_pub = 604800

cache-ttl_priv = 1800

cache-ttl_frontpage = 604800

cache-ttl_feed = 604800

; O_CACHE_TTL_REST
cache-ttl_rest = 604800

cache-ttl_browser = 31557600

cache-login_cookie = ''

cache-vary_group = ''

cache-ttl_status = '403 3600
404 3600
500 3600'


;; -------------------------------------------------- ;;
;; --------------               Purge           ----------------- ;;
;; -------------------------------------------------- ;;

; O_PURGE_ON_UPGRADE
purge-upgrade = true

; O_PURGE_STALE
purge-stale = true

purge-post_all  = false
purge-post_f    = true
purge-post_h    = true
purge-post_p    = true
purge-post_pwrp = true
purge-post_a    = true
purge-post_y    = false
purge-post_m    = true
purge-post_d    = false
purge-post_t    = true
purge-post_pt   = true

purge-timed_urls = ''

purge-timed_urls_time = ''

purge-hook_all = 'switch_theme
wp_create_nav_menu
wp_update_nav_menu
wp_delete_nav_menu
create_term
edit_terms
delete_term
add_link
edit_link
delete_link'


;; -------------------------------------------------- ;;
;; --------------        ESI        ----------------- ;;
;; -------------------------------------------------- ;;

; O_ESI
esi = false

; O_ESI_CACHE_ADMBAR
esi-cache_admbar = true

; O_ESI_CACHE_COMMFORM
esi-cache_commform = true

; O_ESI_NONCE
esi-nonce = 'stats_nonce
subscribe_nonce'

;; -------------------------------------------------- ;;
;; --------------     Utilities     ----------------- ;;
;; -------------------------------------------------- ;;

util-heartbeat = true

util-instant_click = false

util-check_advcache = true

util-no_https_vary = false


;; -------------------------------------------------- ;;
;; --------------               Debug           ----------------- ;;
;; -------------------------------------------------- ;;

; O_DEBUG_DISABLE_ALL
debug-disable_all = false

; O_DEBUG
debug = false

; O_DEBUG_IPS
debug-ips = '127.0.0.1'

; O_DEBUG_LEVEL
debug-level = false

; O_DEBUG_FILESIZE
debug-filesize = 3

; O_DEBUG_COOKIE
debug-cookie = false

; O_DEBUG_COLLAPS_QS
debug-collaps_qs = false

; O_DEBUG_INC
debug-inc = ''

; O_DEBUG_EXC
debug-exc = ''


;; -------------------------------------------------- ;;
;; --------------           DB Optm     ----------------- ;;
;; -------------------------------------------------- ;;

; O_DB_OPTM_REVISIONS_MAX
db_optm-revisions_max = 0

; O_DB_OPTM_REVISIONS_AGE
db_optm-revisions_age = 0


;; -------------------------------------------------- ;;
;; --------------         HTML Optm     ----------------- ;;
;; -------------------------------------------------- ;;

; O_OPTM_CSS_MIN
optm-css_min = false

optm-css_inline_min = false

; O_OPTM_CSS_COMB
optm-css_comb = false

optm-css_comb_priority = false

; O_OPTM_CSS_HTTP2
optm-css_http2 = false

optm-css_exc = ''

; O_OPTM_JS_MIN
optm-js_min = false

optm-js_inline_min = false

; O_OPTM_JS_COMB
optm-js_comb = false

optm-js_comb_priority = false

; O_OPTM_JS_HTTP2
optm-js_http2 = false

; O_OPTM_EXC_JQ
optm-js_exc = ''

optm-ttl = 604800

optm-html_min = false

optm-qs_rm = false

optm-ggfonts_rm = false

; O_OPTM_CSS_ASYNC
optm-css_async = false

; O_OPTM_CCSS_GEN
optm-ccss_gen = true

; O_OPTM_CCSS_ASYNC
optm-ccss_async = true

; O_OPTM_CSS_ASYNC_INLINE
optm-css_async_inline = true

; O_OPTM_CSS_FONT_DISPLAY
optm-css_font_display = false

; O_OPTM_JS_DEFER
optm-js_defer = false

; O_OPTM_JS_INLINE_DEFER
optm-js_inline_defer = false

optm-emoji_rm = false

optm-exc_jq = true

optm-ggfonts_async = false

optm-max_size = 2

optm-rm_comment = false

optm-exc_roles = ''

optm-ccss_con = ''

optm-js_defer_exc = ''

; O_OPTM_DNS_PREFETCH
optm-dns_prefetch = ''

; O_OPTM_DNS_PREFETCH_CTRL
optm-dns_prefetch_ctrl = false

optm-exc = ''

; O_OPTM_CCSS_SEP_POSTTYPE
optm-ccss_sep_posttype = ''

; O_OPTM_CCSS_SEP_URI
optm-ccss_sep_uri = ''

;; -------------------------------------------------- ;;
;; --------------       Object Cache    ----------------- ;;
;; -------------------------------------------------- ;;

object = true

object-kind = false
;object-host = 'localhost'
object-host = '/var/www/memcached.sock'

;object-port = 11211
cache_object_port = ''

object-life = 360

object-persistent = true

object-admin = true

object-transients = true

object-db_id = 0

object-user = ''

object-pswd = ''

object-global_groups = 'users
userlogins
usermeta
user_meta
site-transient
site-options
site-lookup
blog-lookup
blog-details
rss
global-posts
blog-id-cache'

object-non_persistent_groups = 'comment
counts
plugins
wc_session_id'



;; -------------------------------------------------- ;;
;; --------------        Discussion     ----------------- ;;
;; -------------------------------------------------- ;;

; O_DISCUSS_AVATAR_CACHE
discuss-avatar_cache = false

; O_DISCUSS_AVATAR_CRON
discuss-avatar_cron = false

; O_DISCUSS_AVATAR_CACHE_TTL
discuss-avatar_cache_ttl = 604800




;; -------------------------------------------------- ;;
;; --------------                Media          ----------------- ;;
;; -------------------------------------------------- ;;

; O_MEDIA_LAZY
media-lazy = false

; O_MEDIA_LAZY_PLACEHOLDER
media-lazy_placeholder = ''

; O_MEDIA_PLACEHOLDER_RESP
media-placeholder_resp = false

; O_MEDIA_PLACEHOLDER_RESP_COLOR
media-placeholder_resp_color = '#cfd4db'

; O_MEDIA_PLACEHOLDER_RESP_GENERATOR
media-placeholder_resp_generator = false

; O_MEDIA_PLACEHOLDER_RESP_SVG
media-placeholder_resp_svg = '<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><rect width="100%" height="100%" fill="{color}"/></svg>'

; O_MEDIA_PLACEHOLDER_LQIP
media-placeholder_lqip = false

; O_MEDIA_PLACEHOLDER_LQIP_QUAL
media-placeholder_lqip_qual = 4

; O_MEDIA_PLACEHOLDER_RESP_ASYNC
media-placeholder_resp_async = true

; O_MEDIA_IFRAME_LAZY
media-iframe_lazy = false

; O_MEDIA_LAZYJS_INLINE
media-lazyjs_inline = false

; O_MEDIA_LAZY_EXC
media-lazy_exc = ''

; O_MEDIA_LAZY_CLS_EXC
media-lazy_cls_exc = ''

; O_MEDIA_LAZY_PARENT_CLS_EXC
media-lazy_parent_cls_exc = ''

; O_MEDIA_IFRAME_LAZY_CLS_EXC
media-iframe_lazy_cls_exc = ''

; O_MEDIA_IFRAME_LAZY_PARENT_CLS_EXC
media-iframe_lazy_parent_cls_exc = ''

; O_MEDIA_LAZY_URI_EXC
media-lazy_uri_exc = ''




;; -------------------------------------------------- ;;
;; --------------         Image Optm    ----------------- ;;
;; -------------------------------------------------- ;;

img_optm-auto = false

img_optm-cron = true

img_optm-ori = true

img_optm-rm_bkup = false

img_optm-webp = false

img_optm-lossless = false

img_optm-exif = false

img_optm-webp_replace = false

img_optm-webp_attr = 'img.src
div.data-thumb
img.data-src
div.data-large_image
img.retina_logo_url
div.data-parallax-image
video.poster'

img_optm-webp_replace_srcset = false

img_optm-jpg_quality = 82




;; -------------------------------------------------- ;;
;; --------------               Crawler         ----------------- ;;
;; -------------------------------------------------- ;;

crawler = false

crawler-inc_posts = true

crawler-inc_pages = true

crawler-inc_cats = true

crawler-inc_tags = true

crawler-exc_cpt = ''

crawler-order_links = 'date_desc'

crawler-usleep = 500

crawler-run_duration = 400

crawler-run_interval = 600

crawler-crawl_interval = 302400

crawler-threads = 3

crawler-timeout = 30

crawler-load_limit = 1

; O_CRAWLER_SITEMAP
crawler-sitemap = ''

; O_CRAWLER_DROP_DOMAIN
crawler-drop_domain = true

crawler-roles = ''

crawler-cookies = ''




;; -------------------------------------------------- ;;
;; --------------                Misc           ----------------- ;;
;; -------------------------------------------------- ;;

; O_MISC_HTACCESS_FRONT
misc-htaccess_front = ''

; O_MISC_HTACCESS_BACK
misc-htaccess_back = ''

; O_MISC_HEARTBEAT_FRONT
misc-heartbeat_front = false

; O_MISC_HEARTBEAT_FRONT_TTL
misc-heartbeat_front_ttl = 60

; O_MISC_HEARTBEAT_BACK
misc-heartbeat_back = false

; O_MISC_HEARTBEAT_BACK_TTL
misc-heartbeat_back_ttl = 60

; O_MISC_HEARTBEAT_EDITOR
misc-heartbeat_editor = false

; O_MISC_HEARTBEAT_EDITOR_TTL
misc-heartbeat_editor_ttl = 15





;; -------------------------------------------------- ;;
;; --------------                CDN            ----------------- ;;
;; -------------------------------------------------- ;;

cdn = false

cdn-ori = ''

cdn-ori_dir = ''

cdn-exc = ''

cdn-remote_jq = false

cdn-quic = false

cdn-quic_email = ''

cdn-quic_key = ''

cdn-cloudflare = false

cdn-cloudflare_email = ''

cdn-cloudflare_key = ''

cdn-cloudflare_name = ''

cdn-cloudflare_zone = ''

; \`cdn-mapping\` needs to be put in the end with a section tag


;; -------------------------------------------------- ;;
;; --------------                CDN 2          ----------------- ;;
;; -------------------------------------------------- ;;

; <------------ CDN Mapping Example BEGIN -------------------->
; Need to keep the section tag \`[cdn-mapping]\` before list.
;
; NOTE 1) Need to set all child options to make all resources to be replaced without missing.
; NOTE 2) \`url[n]\` option must have to enable the row setting of \`n\`.
; NOTE 3) This section needs to be put in the end of this .ini file
;
; To enable the 2nd mapping record by default, please remove the \`;;\` in the related lines.



[cdn-mapping]

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

; <------------ CDN Mapping Example END ------------------>
EOM
    if [ ! -f ${DOCHM}/wp-content/themes/${THEME}/functions.php.bk ]; then 
        cp ${DOCHM}/wp-content/themes/${THEME}/functions.php ${DOCHM}/wp-content/themes/${THEME}/functions.php.bk
        cked
        ed ${DOCHM}/wp-content/themes/${THEME}/functions.php << END >>/dev/null 2>&1
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
    centos_install_php
    centos_install_memcached
    centos_install_redis
    centos_install_certbot
    install_phpmyadmin
    install_wp_cli
    landing_pg
}

centos_main_config(){
    centos_config_ols
    config_php
    centos_config_memcached
    centos_config_redis
    wp_main_config
}

ubuntu_main_install(){
    ubuntu_install_basic
    ubuntu_install_ols
    ubuntu_install_php
    ubuntu_install_memcached
    ubuntu_install_redis
    ubuntu_install_certbot
    ubuntu_install_postfix
    install_phpmyadmin
    install_wp_cli
    landing_pg
}

ubuntu_main_config(){
    ubuntu_config_ols
    config_php
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