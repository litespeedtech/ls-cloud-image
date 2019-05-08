#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0
# *********************************************************************/
LSWSFD='/usr/local/lsws'
DOCHM='/var/www/html'
PHPCONF='/var/www/phpmyadmin'
LSWSCONF="${LSWSFD}/conf/httpd_config.conf"
WPVHCONF="${LSWSFD}/conf/vhosts/wordpress/vhconf.conf"
EXAMPLECONF="${LSWSFD}/conf/vhosts/Example/vhconf.conf"
PHPINICONF="${LSWSFD}/lsphp73/etc/php/7.3/litespeed/php.ini"
MEMCACHECONF='/etc/memcached.conf'
REDISSERVICE='/lib/systemd/system/redis-server.service'
REDISCONF='/etc/redis/redis.conf'
WPCONSTCONF="${DOCHM}/wp-content/plugins/litespeed-cache/data/const.default.ini"
PHPVER=73
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
            apt-get install ed -y
        elif [ "${OSNAME}" = 'centos' ]; then    
            yum install ed -y
        fi    
    fi    
}

changeowner(){
  chown -R ${USER}:${GROUP} /var/www
}

### ENV
check_os()
{
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
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

prepare(){
    mkdir -p "${DOCHM}.old"
    mkdir -p "${PHPMYPATH}"
    changeowner
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
    systemctl start redis   
    ### phpmyadmin
    if [ ! -f ${PHPCONF}/changelog.php ]; then 
        cd /tmp/ 
        echoG 'Download phpmyadmin'
        wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
        unzip phpMyAdmin-latest-all-languages.zip > /dev/null 2>&1
        rm -f phpMyAdmin-latest-all-languages.zip
        echoG "move phpmyadmin to ${PHPCONF}"
        mv phpMyAdmin-*-all-languages ${PHPCONF}
        echoG 'move phpmyadmin config'
        mv ${PHPCONF}/config.sample.inc.php ${PHPCONF}/config.inc.php
    fi    
}

configols(){
    echoG 'Setting Web Server config'
    ### Change user to www-data
    sed -i "s/nobody/${USER}/g" ${LSWSCONF}
    sed -i "s/nogroup/${GROUP}/g" ${LSWSCONF}
    if [ "${OSNAME}" = 'centos' ]; then 
        yum -y install --reinstall openlitespeed > /dev/null 2>&1
    else    
        apt-get -y install --reinstall openlitespeed > /dev/null 2>&1
    fi    

    ### change doc root to landing page, setup phpmyadmin context
    cat > ${WPVHCONF} <<END 
docRoot                   ${DOCHM}.old/

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

}

landingpg(){
    echoG 'Setting Landing Page'
    curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Static/wp-landing.html \
    -o ${DOCHM}.old/index.html
}

configphp(){
    echoG 'Updating PHP Paremeter'
    NEWKEY='max_execution_time = 360'
    linechange 'max_execution_time' ${PHPINICONF} "${NEWKEY}"

    NEWKEY='post_max_size = 16M'
    linechange 'post_max_size' ${PHPINICONF} "${NEWKEY}"

    NEWKEY='upload_max_filesize = 16M'
    linechange 'upload_max_filesize' ${PHPINICONF} "${NEWKEY}"
}

configobject(){
   echoG 'Setting Object Cache'
    ### Memcached Unix Socket
    service memcached stop
    cat >> "${MEMCACHECONF}" <<END 
-s /var/www/memcached.sock
-a 0770
-p /tmp/memcached.pid
END
    NEWKEY="-u ${USER}"
    linechange '\-u memcache' ${MEMCACHECONF} "${NEWKEY}"
    systemctl daemon-reload > /dev/null 2>&1
    service memcached start

    ### Redis Unix Socket
    service redis stop
    NEWKEY="Group=${GROUP}"
    linechange 'Group=' ${REDISSERVICE} "${NEWKEY}"  
    cat >> "${REDISCONF}" <<END 
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 775
END
    systemctl daemon-reload > /dev/null 2>&1
    service redis-server start
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
}

configwp(){
    echoG 'Setting WordPress'
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
    service lsws restart   
}

dbpasswordfile(){
    if [ -f ${DBPASSPATH} ]; then 
        echoY "${DBPASSPATH} already exist!, will recreate a new file"
        rm -f ${DBPASSPATH}
    fi    
    touch "${DBPASSPATH}"
    cat >> "${DBPASSPATH}" <<EOM
root_mysql_pass="${root_mysql_pass}"
EOM
}

firewalladd(){
    echoG 'Setting Firewall'
    ufw status verbose | grep inactive > /dev/null 2>&1
    if [ $? = 0 ]; then 
        ufw allow 80 > /dev/null 2>&1
        ufw allow 443 > /dev/null 2>&1
        ufw allow 22 > /dev/null 2>&1
        echo "y" | ufw enable > /dev/null 2>&1
        echoG "ufw rules setup success"  
    else
        echoG "ufw already enabled"    
    fi
}

statusck(){
    for ITEM in lsws memcached redis mariadb ufw
    do 
        service ${ITEM} status | grep active > /dev/null 2>&1
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
    rm -f "${NOWPATH}/example.csr" "${NOWPATH}/privkey.pem"
}

### Main
main(){
    START_TIME="$(date -u +%s)"
    prepare
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
echoG 'Auto remove script script itself'
rm -- "$0"
exit 0