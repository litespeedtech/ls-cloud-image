#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0
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
  else
    PROVIDER='undefined'  
  fi
}
providerck
oshmpath()
{
  if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
    HMPATH='/home/ubuntu'
    PUBIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
  elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
    HMPATH='/home/ubuntu'
    PUBIP=$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)    
  else
    HMPATH='/root'
    #PUBIP=$(ifconfig eth0 | grep 'inet '| awk '{printf $2}')
    PUBIP=$(ip -4 route get 8.8.8.8 | awk {'print $7'} | tr -d '\n')
  fi    
}
oshmpath
DBPASSPATH="${HMPATH}/.db_password"


changeowner(){
  chown -R ${USER}:${GROUP} /var/www
}

prepare(){
    mkdir -p "${DOCLAND}"
    changeowner
}

### Upgrade
systemupgrade() {
    echoG 'Updating system'
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
        apt-get update > /dev/null 2>&1
        echo -ne '#####                     (33%)\r'
        DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade > /dev/null 2>&1
        echo -ne '#############             (66%)\r'
        DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade > /dev/null 2>&1
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
installolswp(){
    echo 'Y' | bash <( curl -k https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh ) \
    --lsphp ${PHPVER} \
    --wordpress \
    --wordpresspath ${DOCHM} \
    --dbrootpassword ${root_mysql_pass} \
    --dbname wordpress \
    --dbuser wordpress \
    --dbpassword wordpress
}

confpath(){
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

installpkg(){
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install unzip > /dev/null 2>&1
        echoG 'Install lsphp extensions'
        yum -y install lsphp${PHPVER}-memcached lsphp${PHPVER}-redis lsphp${PHPVER}-opcache > /dev/null 2>&1
        echoG 'Install Memcached'
        yum -y install memcached > /dev/null 2>&1
        echoG 'Install Redis'
        yum -y install redis > /dev/null 2>&1
    else  
        apt-get -y install unzip > /dev/null 2>&1
        echoG 'Install lsphp extensions'
        apt-get -y install lsphp${PHPVER}-memcached lsphp${PHPVER}-redis lsphp${PHPVER}-opcache > /dev/null 2>&1
        echoG 'Install Memcached'
        apt-get -y install memcached > /dev/null 2>&1
        echoG 'Install Redis'
        apt-get -y install redis > /dev/null 2>&1
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
    ### Mariadb 10.3
    cksqlver
    echo ${SQLDBVER} | grep 'MariaDB' | grep '10.3' > /dev/null 2>&1
    if [ $? = 0 ]; then 
        echoG 'Mariadb 10.3 installed'
    else
        apt -y remove mariadb-server-10.* > /dev/null 2>&1
        echoG "Install Mariadb 10.3"
        DEBIAN_FRONTEND='noninteractive' apt-get -y \
            -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' \
            install mariadb-server-10.3 > /dev/null 2>&1
        cksqlver
        echo ${SQLDBVER} | grep 'MariaDB' | grep '10.3' > /dev/null 2>&1
        if [ $? = 0 ]; then 
            echoG 'Mariadb 10.3 installed'
        else
            echoR "Please check Mariadb $(/usr/bin/mysql -V)" 
        fi      
    fi        
}

configols(){
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

landingpg(){
    echoG 'Setting Landing Page'
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Static/wp-landing.html \
    -o ${DOCLAND}/index.html
    if [ -e ${DOCLAND}/index.html ]; then 
        echoG 'Landing Page finished'
    else
        echoR "Please check Landing Page here ${DOCLAND}/index.html"
    fi    
}

configphp(){
    echoG 'Updating PHP Paremeter'
    NEWKEY='max_execution_time = 360'
    linechange 'max_execution_time' ${PHPINICONF} "${NEWKEY}"

    NEWKEY='post_max_size = 16M'
    linechange 'post_max_size' ${PHPINICONF} "${NEWKEY}"

    NEWKEY='upload_max_filesize = 16M'
    linechange 'upload_max_filesize' ${PHPINICONF} "${NEWKEY}"
    echoG 'Finish PHP Paremeter'
}

configobject(){
   echoG 'Setting Object Cache'
    ### Memcached Unix Socket
    service memcached stop > /dev/null 2>&1
    if [ "${OSNAME}" = 'centos' ]; then 
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
        semanage permissive -a memcached_t
        setsebool -P httpd_can_network_memcache 1

    else
        cat >> "${MEMCACHECONF}" <<END 
-s /var/www/memcached.sock
-a 0770
-p /tmp/memcached.pid
END
        NEWKEY="-u ${USER}"
        linechange '\-u memcache' ${MEMCACHECONF} "${NEWKEY}"
    fi    
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

configmysql(){
    echoG 'Setting DataBase'
    if [ -f ${DBPASSPATH} ]; then 
        EXISTSQLPASS=$(grep root_mysql_passs ${HMPATH}/.db_password | awk -F '"' '{print $2}'); 
    fi    
    if [[ ${EXISTSQLPASS} = '' ]]; then  
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



configwp(){
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

dbpasswordfile(){
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

firewalladd(){
    echoG 'Setting Firewall'
    if [ "${OSNAME}" = 'centos' ]; then 
        if [ ! -e /usr/sbin/firewalld ]; then 
            yum -y install firewalld > /dev/null 2>&1
        fi
        service firewalld start 
        systemctl enable firewalld
        for PORT in ${FIREWALLLIST}; do 
            firewall-cmd --permanent --add-port=${PORT}/tcp > /dev/null 2>&1
        done 
        firewall-cmd --reload

        ufw status | grep '80.*ALLOW'
        if [ $? = 0 ]; then 
            echoG 'firewalld rules setup success'
        else 
            echoR 'Please check ufw rules'    
        fi    
    else 
        ufw status verbose | grep inactive > /dev/null 2>&1
        if [ $? = 0 ]; then 
            for PORT in ${FIREWALLLIST}; do
                ufw allow ${PORT} > /dev/null 2>&1
            done    
            echo "y" | ufw enable > /dev/null 2>&1
            echoG "ufw rules setup success"  
        else
            echoG "ufw already enabled"    
        fi
    fi
}

statusck(){
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

rmdummy(){
    echoG 'Remove dummy file'
    rm -f "${NOWPATH}/example.csr" "${NOWPATH}/privkey.pem"
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
        rm -f /etc/update-motd.d/00-header
        rm -f /etc/update-motd.d/10-help-text
        rm -f /etc/update-motd.d/50-landscape-sysinfo
        rm -f /etc/update-motd.d/51-cloudguest
    fi
    echoG 'Finished dummy file'
}

### Main
main(){
    START_TIME="$(date -u +%s)"
    prepare
    systemupgrade
    installolswp
    confpath
    installpkg
    landingpg
    configols
    configphp
    configobject
    configmysql
    configwp
    dbpasswordfile
    changeowner
    firewalladd 
    statusck
    rmdummy
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}
main
#echoG 'Auto remove script itself'
#rm -- "$0"
exit 0