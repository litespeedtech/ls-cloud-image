#!/bin/bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# *********************************************************************/
PANEL=''
PANELPATH=''
EDITION=''
LSDIR='/usr/local/lsws'
CONTEXTPATH="${LSDIR}/Example"
LSHTTPDCFPATH="${LSDIR}/conf/httpd_config.conf"
if [ -e "${LSDIR}/conf/vhosts/wordpress/vhconf.conf" ]; then
    LSVHCFPATH="${LSDIR}/conf/vhosts/wordpress/vhconf.conf"
elif [ -e "${LSDIR}/conf/vhosts/classicpress/vhconf.conf" ]; then
    LSVHCFPATH="${LSDIR}/conf/vhosts/classicpress/vhconf.conf"    
elif [ -e "${LSDIR}/conf/vhosts/joomla/vhconf.conf" ]; then
    LSVHCFPATH="${LSDIR}/conf/vhosts/joomla/vhconf.conf"
elif [ -e "${LSDIR}/conf/vhosts/drupal/vhconf.conf" ]; then
    LSVHCFPATH="${LSDIR}/conf/vhosts/drupal/vhconf.conf"        
else
    LSVHCFPATH="${LSDIR}/conf/vhosts/Example/vhconf.conf"
fi
CLOUDPERINSTPATH='/var/lib/cloud/scripts/per-instance'
DEBIANCNF='/etc/mysql/debian.cnf'
APPNAME_PATH='/opt/.app_name'
WPCT='noneclassified'
OSNAME=''
BANNERNAME=''
BANNERDST=''

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        BANNERDST='/etc/profile.d/99-one-click.sh'
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu   
        BANNERDST='/etc/update-motd.d/99-one-click'
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        BANNERDST='/etc/update-motd.d/99-one-click'
    fi        
}

check_edition()
{
    if [ -d /usr/local/CyberCP ]; then
        PANEL='cyber'
        PANELPATH='/usr/local/CyberCP'
        LSCPPATH='/usr/local/lscp'
        CPCFPATH="${PANELPATH}/CyberCP/settings.py"
        CPSQLPATH='/etc/cyberpanel/mysqlPassword'
        CPIPPATH='/etc/cyberpanel/machineIP'
        BANNERNAME='cyberpanel'
    elif [ -d /usr/local/cpanel ]; then
        PANEL='cpanel'
        PANELPATH='/usr/local/cpanel'
    elif [ -d /usr/local/plesk ];then
        PANEL='plesk'
        PANELPATH='/usr/local/plesk'
    elif [ -d /usr/local/directadmin ];then
        PANEL='direct'
        PANELPATH='/usr/local/directadmin'
    fi
    if [ -e ${LSDIR}/bin/openlitespeed ]; then
        EDITION='openlitespeed'
    elif [ -e ${LSDIR}/bin/litespeed ]; then
        EDITION='litespeed'
    fi 
}

check_provider()
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
        PROVIDER='ali'
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        PROVIDER='azure'   
    elif [ -e /etc/oracle-cloud-agent/ ]; then
        PROVIDER='oracle'             
    elif [ -e /root/StackScript ]; then 
        if grep -q 'linode' /root/StackScript; then 
            PROVIDER='linode'
        fi
    else
        PROVIDER='undefined' 
    fi
}

update_path()
{
    if [ "${PANEL}" = 'cyber' ]; then 
        PHPMYPATH="${PANELPATH}/public/phpmyadmin"
        WPCT="${PROVIDER}_ols_cyberpanel"
        if [ -e "${APPNAME_PATH}" ]; then
            if grep -i 'cyberpanel-joomla' "${APPNAME_PATH}" >/dev/null; then
                WPCT="${PROVIDER}_ols_joomla"
                BANNERNAME='cyberjoomla'
            elif grep -i 'cyberpanel-drupal' "${APPNAME_PATH}" >/dev/null; then
                WPCT="${PROVIDER}_ols_drupal"
                BANNERNAME='cyberdrupal'
            elif grep -i 'cyberpanel-wordpress' "${APPNAME_PATH}" >/dev/null; then
                WPCT="${PROVIDER}_ols_wordpress"
                BANNERNAME='cyberwordpress'
            fi
        fi
        APP_DOVECOT_CF='/etc/dovecot/dovecot-sql.conf.ext'
        APP_POSTFIX_DOMAINS_CF='/etc/postfix/mysql-virtual_domains.cf'
        APP_POSTFIX_EMAIL2EMAIL_CF='/etc/postfix/mysql-virtual_email2email.cf'
        APP_POSTFIX_FORWARDINGS_CF='/etc/postfix/mysql-virtual_forwardings.cf'
        APP_POSTFIX_MAILBOXES_CF='/etc/postfix/mysql-virtual_mailboxes.cf'

        if [ ${OSNAME} = 'ubuntu' ] || [ ${OSNAME} = 'debian' ]; then
            APP_PUREFTP_CF='/etc/pure-ftpd/pureftpd-mysql.conf'
            APP_PUREFTPDB_CF='/etc/pure-ftpd/db/mysql.conf'
            APP_POWERDNS_CF='/etc/powerdns/pdns.conf'
        elif [ ${OSNAME} = 'centos' ]; then
            APP_PUREFTP_CF='/etc/pure-ftpd/pureftpd-mysql.conf'
            APP_PUREFTPDB_CF='/etc/pure-ftpd/pureftpd-mysql.conf'
            APP_POWERDNS_CF='/etc/pdns/pdns.conf'
        fi        
    elif [ "${PANEL}" = '' ]; then
        PHPMYPATH='/var/www/phpmyadmin' 
        DOCPATH='/var/www/html'
        if [ ${EDITION} = 'litespeed' ]; then
            WPCT="${PROVIDER}_lsws"
            BANNERNAME='litespeed'         
        elif [ -f '/usr/bin/node' ] && [ "$(grep -n 'appType.*node' ${LSVHCFPATH})" != '' ]; then
            APPLICATION='NODE'
            WPCT="${PROVIDER}_ols_node"
            BANNERNAME='nodejs'
        elif [ -f '/usr/bin/ruby' ] && [ "$(grep -n 'appType.*rails' ${LSVHCFPATH})" != '' ]; then
            APPLICATION='RUBY'
            WPCT="${PROVIDER}_ols_ruby"
            BANNERNAME='ruby'
        elif [ -f '/usr/bin/python3' ] && [ "$(grep -n 'appType.*wsgi' ${LSVHCFPATH})" != '' ]; then
            APPLICATION='PYTHON'
            CONTEXTPATH="${LSDIR}/Example/html/demo/demo/settings.py"
            WPCT="${PROVIDER}_ols_python"
            BANNERNAME='django'      
        else
            APPLICATION='CMS' 
            DOCPATH='/var/www/html.old'
            if [ -d ${DOCPATH}/administrator ]; then 
                WPCT="${PROVIDER}_ols_joomla"
                BANNERNAME='joomla'
            elif [ -d ${DOCPATH}/web/sites ]; then 
                WPCT="${PROVIDER}_ols_drupal"
                BANNERNAME='drupal'                
            else 
                grep -i ClassicPress ${DOCPATH}/license.txt >/dev/null
                if [ ${?} = 0 ]; then
                    WPCT="${PROVIDER}_ols_classicpress"
                    BANNERNAME='classicpress'       
                else
                    WPCT="${PROVIDER}_ols_wordpress"
                    BANNERNAME='wordpress'
                fi
            fi    
        fi 
    fi
    PHPMYCFPATH="${PHPMYPATH}/config.inc.php"
    if [ -f "${DOCPATH}/wp-config.php" ]; then
        WPCFPATH="${DOCPATH}/wp-config.php"
    fi
}

os_home_path()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
        PUBIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
        PUBIP=$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)   
    elif [ ${PROVIDER} = 'ali' ]; then
        HMPATH='/root'
        PUBIP=$(curl http://100.100.100.200/latest/meta-data/eipv4)   
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        HMPATH='/root'
        PUBIP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")
    elif [ -e /etc/oracle-cloud-agent/ ] && [ -d /home/ubuntu ]; then
        HMPATH='/home/ubuntu'
        PUBIP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")     
    else
        HMPATH='/root'
        PUBIP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")
    fi   
}

main_env_check(){
    check_os
    check_edition
    check_provider
    update_path
    os_home_path
}
main_env_check

rm_dummy(){
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
        rm -f /etc/update-motd.d/00-header
        rm -f /etc/update-motd.d/10-help-text
        rm -f /etc/update-motd.d/50-landscape-sysinfo
        rm -f /etc/update-motd.d/50-motd-news
        rm -f /etc/update-motd.d/51-cloudguest
        rm -f /etc/profile.d/cyberpanel.sh
        if [ -f /etc/legal ]; then
            mv /etc/legal /etc/legal.bk
        fi
        if [ "${PROVIDER}" = 'ali' ]; then
            mv /etc/motd /etc/motd.bk
        fi
    fi
}

ct_version()
{
    curl "https://wpapi.quic.cloud/wpdata/1click_ver?t=image&src=${WPCT}" > /dev/null 2>&1
    echo "cloud-${PROVIDER}" > ${LSDIR}/PLAT
}

setup_domain(){
    if [ ! -e /opt/domainsetup.sh ] && [ ${EDITION} != 'litespeed' ]; then
        STATUS="$(curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Setup/domainsetup.sh \
        -o /opt/domainsetup.sh -w "%{http_code}")"
        if [ ${?} != 0 ] || [ "${STATUS}" != '200' ]; then
            curl -s https://cloud.litespeed.sh/Setup/domainsetup.sh -o /opt/domainsetup.sh
        fi
        chmod +x /opt/domainsetup.sh
    fi    
}    
setup_banner(){
    if [ ! -e ${BANNERDST} ]; then
        STATUS="$(curl -s https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Banner/${BANNERNAME} \
        -o ${BANNERDST} -w "%{http_code}")"  
        if [ ${?} != 0 ] || [ "${STATUS}" != '200' ]; then
            curl -s https://cloud.litespeed.sh/Banner/${BANNERNAME} -o ${BANNERDST}
        fi  
        chmod +x ${BANNERDST}
    fi
}

db_passwordfile()
{
    if [ "${APPLICATION}" = 'CMS' ] || [ "${PANEL}" = 'cyber' ]; then
        if [ ! -e "${HMPATH}/.db_password" ]; then
            touch "${HMPATH}/.db_password"
            DBPASSPATH="${HMPATH}/.db_password"
        else
            DBPASSPATH="${HMPATH}/.db_password"
            ori_root_mysql_pass=$(grep 'root_mysql_pass' ${DBPASSPATH} | awk -F'=' '{print $2}' | tr -d '"') 
        fi
    fi 
}
litespeed_passwordfile()
{
    if [ ! -e "${HMPATH}/.litespeed_password" ]; then
        touch "${HMPATH}/.litespeed_password"
    fi
    LSPASSPATH="${HMPATH}/.litespeed_password"
}

gen_lsws_pwd()
{
    ADMIN_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    ENCRYPT_PASS=$(${LSDIR}/admin/fcgi-bin/admin_php* -q ${LSDIR}/admin/misc/htpasswd.php ${ADMIN_PASS})
}

gen_sql_pwd(){
    root_mysql_pass=$(openssl rand -hex 24)
    app_mysql_pass=$(openssl rand -hex 24)
    debian_sys_maint_mysql_pass=$(openssl rand -hex 24)
}
gen_salt_pwd(){
    GEN_SALT=$(</dev/urandom tr -dc 'a-zA-Z0-9!@#%^&*()-_[]{}<>~+=' | head -c 64 | sed -e 's/[\/&]/\&/g')
}
gen_secretkey(){
    GEN_SECRET=$(</dev/urandom tr -dc 'a-zA-Z0-9!@#%^&*()-_[]{}<>~+=' | head -c 50 | sed -e 's/[\/&]/\&/g')
}
gen_selfsigned_cert()
{ 
    SSL_HOSTNAME=webadmin
    csr="${SSL_HOSTNAME}.csr"
    key="${SSL_HOSTNAME}.key"
    cert="${SSL_HOSTNAME}.crt"

    openssl req -new -passin pass:password -passout pass:password -out ${csr} >/dev/null 2>&1 <<csrconf
US
NJ
Virtual
LiteSpeedCommunity
Testing
webadmin
.
.
.
csrconf
    [ -f ${csr} ] && openssl req -text -noout -in ${csr} >/dev/null 2>&1
    openssl rsa -in privkey.pem -passin pass:password -passout pass:password -out ${key} >/dev/null 2>&1
    openssl x509 -in ${csr} -out ${cert} -req -signkey ${key} -days 1000 >/dev/null 2>&1
    rm -f ${SSL_HOSTNAME}.csr
    rm -f privkey.pem
}

linechange(){
    LINENUM=$(grep -n -m 1 "${1}" ${2} | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi 
}

lscpd_cert_update()
{
    if [ "${PANEL}" = 'cyber' ]; then
        cp ${SSL_HOSTNAME}.crt ${LSCPPATH}/conf/cert.pem
        cp ${SSL_HOSTNAME}.key ${LSCPPATH}/conf/key.pem
    fi 
}

web_admin_update()
{
    echo "admin:${ENCRYPT_PASS}" > ${LSDIR}/admin/conf/htpasswd
    echo "admin_pass=${ADMIN_PASS}" > ${LSPASSPATH}
    mv ${SSL_HOSTNAME}.crt ${LSDIR}/admin/conf/${SSL_HOSTNAME}.crt
    mv ${SSL_HOSTNAME}.key ${LSDIR}/admin/conf/${SSL_HOSTNAME}.key
}

panel_admin_update()
{
    if [ "${PANEL}" = 'cyber' ]; then  
        if [ -f /usr/local/CyberPanel/bin/python2 ]; then
            /usr/local/CyberPanel/bin/python2 ${PANELPATH}/plogical/adminPass.py --password ${ADMIN_PASS}
        else
            /usr/local/CyberPanel/bin/python ${PANELPATH}/plogical/adminPass.py --password ${ADMIN_PASS}
        fi    
    fi 
}

panel_sshkey_update()
{
    if [ "${PANEL}" = 'cyber' ]; then
        echo 'y' | ssh-keygen -f /root/.ssh/cyberpanel -t rsa -N ''
    fi
}

panel_IP_update()
{
    if [ "${PANEL}" = 'cyber' ]; then
        echo "${PUBIP}" > ${CPIPPATH}
    fi
}

passftp_IP_update(){
    if [ "${PANEL}" = 'cyber' ]; then
        if [ ${OSNAME} = 'ubuntu' ] || [ ${OSNAME} = 'debian' ]; then
            cat "${CPIPPATH}" > /etc/pure-ftpd/conf/ForcePassiveIP
        fi    
    fi
}

filepermission_update(){
    chmod 600 ${DBPASSPATH}
    chmod 600 ${LSPASSPATH}
}

update_secretkey(){
    if [ "${PANEL}" = 'cyber' ]; then
        SECRETPATH=${CPCFPATH}
    elif [ "${APPLICATION}" = 'PYTHON' ]; then 
        SECRETPATH=${CONTEXTPATH} 
    fi 
    LINENUM=$(grep -n 'SECRET_KEY' ${SECRETPATH} | cut -d: -f 1)
    sed -i "${LINENUM}d" ${SECRETPATH}
    NEWKEY="SECRET_KEY = '${GEN_SECRET}'"
    sed -i "${LINENUM}i${NEWKEY}" ${SECRETPATH}
}

update_CPsqlpwd(){
    PREPWD=$(cat ${CPSQLPATH})
    mysql -uroot -p${PREPWD} \
        -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${root_mysql_pass}');"

    for LINENUM in $(grep -n "'PASSWORD':" ${CPCFPATH} | cut -d: -f 1);
    do
        NEWDBPWD="        'PASSWORD': '${root_mysql_pass}',"
        sed -i "${LINENUM}s/.*/${NEWDBPWD}/" ${CPCFPATH}
    done
    sed -i "1s/.*/${root_mysql_pass}/" ${CPSQLPATH}
    ### cyberpanel user   
    mysql -uroot -p${root_mysql_pass} \
        -e "SET PASSWORD FOR 'cyberpanel'@'localhost' = PASSWORD('${root_mysql_pass}');"

    ### update cyberpanel to applications conf files
    #### dovecot
    NEWKEY="connect = host=localhost dbname=cyberpanel user=cyberpanel password=${root_mysql_pass} port=3306"
    linechange 'password=' ${APP_DOVECOT_CF} "${NEWKEY}"

    #### postfix
    NEWKEY="password = ${root_mysql_pass}"
    linechange 'password =' ${APP_POSTFIX_DOMAINS_CF} "${NEWKEY}"
    linechange 'password =' ${APP_POSTFIX_EMAIL2EMAIL_CF} "${NEWKEY}"
    linechange 'password =' ${APP_POSTFIX_FORWARDINGS_CF} "${NEWKEY}"
    linechange 'password =' ${APP_POSTFIX_MAILBOXES_CF} "${NEWKEY}"

    #### pure-ftpd
    NEWKEY="MYSQLPassword ${root_mysql_pass}"
    linechange 'MYSQLPassword' ${APP_PUREFTP_CF} "${NEWKEY}"
    linechange 'MYSQLPassword' ${APP_PUREFTPDB_CF} "${NEWKEY}"
    if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
        systemctl restart pure-ftpd-mysql.service
    elif [ "${OSNAME}" = 'centos' ]; then
        service pure-ftpd restart
    fi   
    #### powerdns
    NEWKEY="gmysql-password=${root_mysql_pass}"
    linechange 'gmysql-password' ${APP_POWERDNS_CF} "${NEWKEY}"

    service lscpd restart
}

renew_wp_pwd(){
    NEWDBPWD="define('DB_PASSWORD', '${app_mysql_pass}');"
    linechange 'DB_PASSWORD' ${WPCFPATH} "${NEWDBPWD}"
}

replace_litenerip(){
    if [ "${EDITION}" != 'litespeed' ]; then 
        if [ "${PROVIDER}" = 'do' ] && [ "${PANEL}" = '' ]; then 
            for LINENUM in $(grep -n 'map' ${LSHTTPDCFPATH} | cut -d: -f 1)
            do
                if [ -e /var/www/html ] || [ -e /var/www/html.old ]; then 
                    if [ "${BANNERNAME}" = 'wordpress' ]; then
                        NEWDBPWD="  map                     wordpress ${PUBIP}"
                    elif [ "${BANNERNAME}" = 'classicpress' ]; then
                        NEWDBPWD="  map                     classicpress ${PUBIP}"
                    elif [ "${BANNERNAME}" = 'joomla' ]; then
                        NEWDBPWD="  map                     joomla ${PUBIP}"
                    elif [ "${BANNERNAME}" = 'drupal' ]; then
                        NEWDBPWD="  map                     drupal ${PUBIP}"                    
                    fi    
                else
                    NEWDBPWD="  map                     Example ${PUBIP}"
                fi    
                sed -i "${LINENUM}s/.*/${NEWDBPWD}/" ${LSHTTPDCFPATH}
            done 
        fi    
    fi
}

update_sql_pwd(){
    mysql -uroot -p${ori_root_mysql_pass} \
        -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${root_mysql_pass}');"
    if [ "${BANNERNAME}" = 'wordpress' ]; then
        mysql -uroot -p${root_mysql_pass} \
            -e "SET PASSWORD FOR 'wordpress'@'localhost' = PASSWORD('${app_mysql_pass}');"
        mysql -uroot -p${root_mysql_pass} \
            -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost"
    elif [ "${BANNERNAME}" = 'classicpress' ]; then
        mysql -uroot -p${root_mysql_pass} \
            -e "SET PASSWORD FOR 'classicpress'@'localhost' = PASSWORD('${app_mysql_pass}');"
        mysql -uroot -p${root_mysql_pass} \
            -e "GRANT ALL PRIVILEGES ON classicpress.* TO classicpress@localhost"
    elif [ "${BANNERNAME}" = 'joomla' ]; then
        mysql -uroot -p${root_mysql_pass} \
            -e "SET PASSWORD FOR 'joomla'@'localhost' = PASSWORD('${app_mysql_pass}');"
        mysql -uroot -p${root_mysql_pass} \
            -e "GRANT ALL PRIVILEGES ON joomla.* TO joomla@localhost"
    elif [ "${BANNERNAME}" = 'drupal' ]; then
        mysql -uroot -p${root_mysql_pass} \
            -e "SET PASSWORD FOR 'drupal'@'localhost' = PASSWORD('${app_mysql_pass}');"
        mysql -uroot -p${root_mysql_pass} \
            -e "GRANT ALL PRIVILEGES ON drupal.* TO drupal@localhost"            
    fi    
}

add_sql_debian(){
    if [ ! -e ${DEBIANCNF} ]; then
        touch ${DEBIANCNF}
        chmod 600 ${DEBIANCNF}
    fi
    sudo cat >> ${DEBIANCNF} <<EOM
[client]
host     = localhost
user     = root
password = ${root_mysql_pass}
socket   = /var/run/mysqld/mysqld.sock
EOM

}

renew_wpsalt(){
    for KEY in "'AUTH_KEY'" "'SECURE_AUTH_KEY'" "'LOGGED_IN_KEY'" "'NONCE_KEY'" "'AUTH_SALT'" "'SECURE_AUTH_SALT'" "'LOGGED_IN_SALT'" "'NONCE_SALT'"
    do
        LINENUM=$(grep -n "${KEY}" ${WPCFPATH} | cut -d: -f 1)
        sed -i "${LINENUM}d" ${WPCFPATH}
        NEWSALT="define(${KEY}, '${GEN_SALT}');"
        sed -i "${LINENUM}i${NEWSALT}" ${WPCFPATH}
    done
}

renew_blowfish(){
    LINENUM=$(grep -n "'blowfish_secret'" ${PHPMYCFPATH} | cut -d: -f 1)
    sed -i "${LINENUM}d" ${PHPMYCFPATH}
    NEW_SALT="\$cfg['blowfish_secret'] = '${GEN_SALT}';"
    sed -i "${LINENUM}i${NEW_SALT}" ${PHPMYCFPATH}
}

updaterootpwdfile(){
    rm -f ${DBPASSPATH}
    cat >> ${DBPASSPATH} <<EOM
root_mysql_pass="${root_mysql_pass}"
EOM
}

update_CPpwdfile(){
    rm -f ${DBPASSPATH}
    cat >> ${DBPASSPATH} <<EOM
root_mysql_pass="${root_mysql_pass}"
cyberpanel_mysql_pass="${root_mysql_pass}"
EOM
}

update_pwd_file(){
    rm -f ${DBPASSPATH}
    if [ "${BANNERNAME}" = 'wordpress' ]; then    
        cat >> ${DBPASSPATH} <<EOM
root_mysql_pass="${root_mysql_pass}"
wordpress_mysql_pass="${app_mysql_pass}"
EOM
    elif [ "${BANNERNAME}" = 'classicpress' ]; then 
        cat >> ${DBPASSPATH} <<EOM 
root_mysql_pass="${root_mysql_pass}"
classicpress_mysql_pass="${app_mysql_pass}"
EOM
    elif [ "${BANNERNAME}" = 'joomla' ]; then 
        cat >> ${DBPASSPATH} <<EOM 
root_mysql_pass="${root_mysql_pass}"
joomla_mysql_pass="${app_mysql_pass}"
EOM
    elif [ "${BANNERNAME}" = 'drupal' ]; then 
        cat >> ${DBPASSPATH} <<EOM 
root_mysql_pass="${root_mysql_pass}"
drupal_mysql_pass="${app_mysql_pass}"
EOM
    fi    
}

upgrade_cyberpanel() {
    if [ -e /tmp/upgrade.py ]; then
        sudo rm -rf /tmp/upgrade.py
    fi
    wget --quiet http://cyberpanel.net/upgrade.py
    sudo chmod 755 /tmp/upgrade.py
    sudo python /tmp/upgrade.py
}

setup_after_ssh(){
    sudo cat << EOM > /etc/profile.d/afterssh.sh
#!/bin/bash
sudo mv /var/www/html/ /var/www/html.land/
sudo mv /var/www/html.old/ /var/www/html/
sudo systemctl stop lsws >/dev/null 2>&1
sudo /usr/local/lsws/bin/lswsctrl stop >/dev/null 2>&1
sleep 1
if [[ \$(sudo ps -ef | grep -i 'openlitespeed' | grep -v 'grep') != '' ]]; then
  sudo kill -9 \$(sudo ps -ef | grep -v 'grep' | grep -i 'openlitespeed' | grep -i 'main' | awk '{print \$2}')
fi
sudo systemctl start lsws
sudo rm -f '/etc/profile.d/afterssh.sh'
EOM
    sudo chmod 755 /etc/profile.d/afterssh.sh
}

setup_after_ssh_drupal(){
    sudo cat << EOM > /etc/profile.d/afterssh.sh
#!/bin/bash
sudo mv /var/www/html/ /var/www/html.land/
sudo mv /var/www/html.old/ /var/www/html/
export COMPOSER_ALLOW_SUPERUSER=1
cd /var/www/html
echo '############# Auto-Installation (one time only) ###############'
sudo vendor/bin/drush -y site-install standard --db-url=mysql://drupal:${app_mysql_pass}@127.0.0.1/drupal --account-name=admin --account-pass=${ADMIN_PASS}
sudo vendor/bin/drush -y config-set system.performance css.preprocess 0 -q
sudo vendor/bin/drush -y config-set system.performance js.preprocess 0 -q
sudo vendor/bin/drush cache-rebuild -q
sudo sed -i 's|docRoot.*html/|docRoot                   '/var/www/html/web/'|g' /usr/local/lsws/conf/vhosts/drupal/vhconf.conf >/dev/null
sudo vendor/bin/drush pm:enable lite_speed_cache
sudo systemctl stop lsws >/dev/null 2>&1
sudo /usr/local/lsws/bin/lswsctrl stop >/dev/null 2>&1
sleep 1
if [[ \$(sudo ps -ef | grep -i 'openlitespeed' | grep -v 'grep') != '' ]]; then
  sudo kill -9 \$(sudo ps -ef | grep -v 'grep' | grep -i 'openlitespeed' | grep -i 'main' | awk '{print \$2}')
fi
sudo chmod 755 /etc/profile.d/afterssh.sh
if [ -f /etc/redhat-release ]; then
    USER='nobody'
    GROUP='nobody'
else    
    USER='www-data'
    GROUP='www-data'     
fi 
chown -R \${USER}:\${GROUP} /var/www/html/web/ 
sudo systemctl start lsws
echo '#############################################################'
sudo rm -f '/etc/profile.d/afterssh.sh'
EOM
}

update_conntrack_max(){
    if [ "${PROVIDER}" = 'do' ] || [ "${PROVIDER}" = 'vultr' ] || [ "${PROVIDER}" = 'linode' ]; then
        grep nf_conntrack_max /etc/sysctl.conf >/dev/null 2>&1
        if [ ${?} = 1 ]; then
            sysctl -w net.netfilter.nf_conntrack_max=2097152 >/dev/null
            echo "net.netfilter.nf_conntrack_max=2097152" >> /etc/sysctl.conf
        fi
    fi    
}

add_profile(){
    if [ ${EDITION} != 'litespeed' ]; then
        echo "sudo /opt/domainsetup.sh" >> /etc/profile
    fi    
}

add_hosts(){
    if [ -d /home/ubuntu ] || [ "${PROVIDER}" = 'vultr' ] || [ "${PROVIDER}" = 'azure' ]; then
        NEWKEY="127.0.0.1 localhost $(hostname)"
        linechange '127.0.0.1' /etc/hosts "${NEWKEY}"
    fi
}

lsws_license(){
    if [ ${EDITION} = 'litespeed' ]; then 
        cd ${LSDIR}/conf
        wget -q --no-check-certificate http://license.litespeedtech.com/reseller/trial.key
        systemctl start lsws
    fi    
}

install_rainloop(){
    RAINLOOP_PATH="${PANELPATH}/public/rainloop"
    RAINDATA_PATH="${LSCPPATH}/cyberpanel/rainloop/data"
    if [ ! -e ${RAINLOOP_PATH} ]; then
        mkdir -p ${RAINLOOP_PATH}; cd ${RAINLOOP_PATH}
        wget -q http://www.rainloop.net/repository/webmail/rainloop-community-latest.zip
        if [ -e rainloop-community-latest.zip ]; then
            unzip -qq rainloop-community-latest.zip
            rm -f rainloop-community-latest.zip
            find . -type d -exec chmod 755 {} \;
            find . -type f -exec chmod 644 {} \;
            NEWKEY="\$sCustomDataPath = '${RAINDATA_PATH}';"
            linechange "sCustomDataPath = '" ${RAINLOOP_PATH}/rainloop/v/*/include.php "${NEWKEY}"
            chown -R lscpd:lscpd ${RAINDATA_PATH}/
        else
            echo 'No rainloop-community-latest.zip file'
        fi
    fi
}

install_firewalld(){
    if [ "${OSNAME}" != 'centos' ]; then
        FWDCMD='/usr/bin/firewall-cmd --permanent --zone=public --add-rich-rule'
        /usr/bin/apt update -y
        /usr/bin/apt-get install firewalld -y
        /bin/systemctl enable firewalld

        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="8090" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="8090" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="80" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="80" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="443" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="443" accept'
        /usr/bin/firewall-cmd --add-service=ssh --permanent
        /usr/bin/firewall-cmd --add-service=ftp --permanent
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="25" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="25" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="587" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="587" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="465" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="465" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="110" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="110" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="143" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="143" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="993" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="993" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="udp" port="53" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="udp" port="53" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="53" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="53" accept'
        ${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="40110-40210" accept'
        ${FWDCMD}='rule family="ipv6" port protocol="tcp" port="40110-40210" accept'

        /usr/bin/firewall-cmd --reload
    fi    
}

check_version() {
    VERSION_1=$1
    OPTION=$2
    VERSION_2=$3

    VERSION_1=${VERSION_1//./ }
    VERSION_2=${VERSION_2//./ }

    VERSION_1_MAJOR=$(awk '{print $1}' <<< "${VERSION_1}")
    VERSION_1_MINOR=$(awk '{print $2}' <<< "${VERSION_1}")
    VERSION_1_PATCH=$(awk '{print $3}' <<< "${VERSION_1}")

    VERSION_2_MAJOR=$(awk '{print $1}' <<< "${VERSION_2}")
    VERSION_2_MINOR=$(awk '{print $2}' <<< "${VERSION_2}")
    VERSION_2_PATCH=$(awk '{print $3}' <<< "${VERSION_2}")

    if [[ "${OPTION}" == '>' ]]; then
        if [[ "${VERSION_1_MAJOR}" -gt "${VERSION_2_MAJOR}" ]] || [[ "${VERSION_1_MINOR}" -gt "${VERSION_2_MINOR}" ]] || [[ "${VERSION_1_PATCH}" -gt "${VERSION_2_PATCH}" ]]; then
            return 0
        fi
    elif [[ "${OPTION}" == '<' ]]; then
        if [[ "${VERSION_1_MAJOR}" -lt "${VERSION_2_MAJOR}" ]] || [[ "${VERSION_1_MINOR}" -lt "${VERSION_2_MINOR}" ]] || [[ "${VERSION_1_PATCH}" -lt "${VERSION_2_PATCH}" ]]; then
            return 0
        fi
    elif [[ "${OPTION}" == '=' ]]; then
        if [[ "${VERSION_1_MAJOR}" -eq "${VERSION_2_MAJOR}" ]] && [[ "${VERSION_1_MINOR}" -eq "${VERSION_2_MINOR}" ]] && [[ "${VERSION_1_PATCH}" -eq "${VERSION_2_PATCH}" ]]; then
            return 0
        fi
    fi

    return 1
}

update_phpmyadmin() {
    INSTALL_PATH="${PHPMYPATH}" 
    LOCAL_VERSION=$(cat ${INSTALL_PATH}/ChangeLog | head -n4 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]')
    LATEST_VERSION=$(curl -s https://www.phpmyadmin.net/home_page/version.php | head -n1)
    URL="https://files.phpmyadmin.net/phpMyAdmin/${LATEST_VERSION}/phpMyAdmin-${LATEST_VERSION}-all-languages.zip"

    if check_version "${LOCAL_VERSION}" '<' "${LATEST_VERSION}"; then
        cd /tmp/
        if [ -e "phpMyAdmin-${LATEST_VERSION}-all-languages.zip" ]; then
            sudo rm -f phpMyAdmin-${LATEST_VERSION}-all-languages.zip
        fi
        curl -Os ${URL}
        unzip -qq phpMyAdmin-${LATEST_VERSION}-all-languages.zip
        cp -pr phpMyAdmin-${LATEST_VERSION}-all-languages/* ${INSTALL_PATH}/
        if [ "${PANEL}" = 'cyber' ]; then
            USER='root'
            GROUP='root'
        elif [ -f /etc/redhat-release ]; then
            USER='nobody'
            GROUP='nobody'
        else    
            USER='www-data'
            GROUP='www-data'     
        fi 
        chown -R ${USER}:${GROUP} ${INSTALL_PATH}/
        sudo rm -rf /tmp/phpMyAdmin-${LATEST_VERSION}-all-languages*
    fi
}

main_cyber()
{
    panel_admin_update
    panel_sshkey_update
    panel_IP_update
    passftp_IP_update
    update_phpmyadmin
    update_CPsqlpwd
    update_secretkey
    update_CPpwdfile
    install_rainloop
    filepermission_update
    renew_blowfish
    install_firewalld      
}

main_cms()
{
    update_sql_pwd
    add_sql_debian
    if [ "${BANNERNAME}" = 'joomla' ]; then
        update_pwd_file
        update_phpmyadmin
        renew_blowfish
        setup_after_ssh
    elif [ "${BANNERNAME}" = 'drupal' ]; then
        update_pwd_file
        update_phpmyadmin
        renew_blowfish
        setup_after_ssh_drupal            
    else
        renew_wp_pwd
        update_pwd_file
        renew_wpsalt
        update_phpmyadmin
        renew_blowfish
        setup_after_ssh
    fi  
}

maincloud(){
    setup_domain
    setup_banner
    litespeed_passwordfile
    ct_version
    gen_lsws_pwd
    add_hosts
    gen_selfsigned_cert
    lscpd_cert_update
    web_admin_update
    replace_litenerip
    db_passwordfile
    update_conntrack_max
    lsws_license
    gen_sql_pwd
    gen_salt_pwd
    gen_secretkey
    rm_dummy
    add_profile
    if [ "${PANEL}" = 'cyber' ]; then
        main_cyber
    elif [ "${APPLICATION}" = 'PYTHON' ]; then
        update_secretkey
    elif [ "${APPLICATION}" = 'CMS' ]; then
        main_cms   
    fi
}

maincloud
rm -f ${CLOUDPERINSTPATH}/per-instance.sh
