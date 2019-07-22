#!/bin/bash
# /********************************************************************
# LiteSpeed domain setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0.1
# *********************************************************************/
MY_DOMAIN=''
MY_DOMAIN2=''
WWW_PATH='/var/www'
LSDIR='/usr/local/lsws'
WEBCF="${LSDIR}/conf/httpd_config.conf"
VHDIR="${LSDIR}/conf/vhosts"
EMAIL='localhost'
WWW='FALSE'
BOTCRON='/etc/cron.d/certbot'
PLUGINLIST="litespeed-cache.zip all-in-one-seo-pack.zip all-in-one-wp-migration.zip \
google-analytics-for-wordpress.zip jetpack.zip wp-mail-smtp.zip"
CKREG="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*\
@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
THEME='twentynineteen'
PHPVER=lsphp73
USER='www-data'
GROUP='www-data'
DOMAIN_PASS='ON'
DOMAIN_SKIP='OFF'
EMAIL_SKIP='OFF'
SILENT='OFF'
TMP_YN='OFF'
ISSUECERT='OFF'
FORCE_HTTPS='OFF'
WORDPRESS='OFF'

echoR() {
    echo -e "\e[31m${1}\e[39m"
}
echoG() {
    echo -e "\e[32m${1}\e[39m"
}
echoY() {
    echo -e "\e[33m${1}\e[39m"
}
echoB() {
    echo -e "\033[1;4;94m${1}\033[0m"
}
show_help() {
    case ${1} in
    "1")
        echo "########################################################################################"
        echoY "-d  or --domain:      for domain, if you wish to add www domain , please attach www"
        echoY "-le or --letsencrypt: issue let's ecnrypt certificate, must follow with E-mail address."
        echoY "-f  or --force-https: this will add a force HTTPS rule in htaccess file"
        echoY "-w  or --wordpress:   this will install a Wordpress with LiteSpeed Cache plugin."
        echoY "Example: ./vhsetup.sh -d www.example.com -le admin@example.com -f -w"
        echoY "Above example will create a virtual host with www.example.com and example.com domain"
        echoY "issue and install Let's encrypt certificate and Wordpress with LiteSpeed Cache plugin."
        echo "########################################################################################"
        echo ''
        exit 0
    ;;    
    "2")
        echoY "If you need to install cert manually later, please check:" 
        echoB "https://docs.litespeedtech.com/cloud/OPT-LETSHTTPS/"
        echo ''
    ;;  
    "3")
        echo "Please make sure you have ${HM_PATH}/.db_password file with content:"
        echoY 'root_mysql_pass="YOUR_DB_PASSWORD"'
    ;;  
    esac
}
check_os() {
    if [ -f /etc/redhat-release ]; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
    elif [ -f /etc/lsb-release ]; then
        OSNAME=ubuntu
    elif [ -f /etc/debian_version ]; then
        OSNAME=debian
    fi
}
check_provider()
{
    if [ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ]; then 
        PROVIDER='aws'
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'      
    else
        PROVIDER='undefined'  
    fi
}
check_home_path()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
        HM_PATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
        HM_PATH='/home/ubuntu'  
    else
        HM_PATH='/root'
    fi    
}
check_root(){
    if [ $(id -u) -ne 0 ]; then
        echoR "Please run this script as root user or use sudo"
        exit 2
    fi
}
check_process(){
    ps aux | grep ${1} | grep -v grep >/dev/null 2>&1
}
install_ed() {
    if [ -f /bin/ed ]; then
        echoG "ed exist"
    else
        echoG "no ed, ready to install"
        if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
            apt-get install ed -y >/dev/null 2>&1
        elif [ "${OSNAME}" = 'centos' ]; then
            yum install ed -y >/dev/null 2>&1
        fi
    fi
}
create_file(){
    if [ ! -f ${1} ]; then
        touch ${1}
    fi
}
create_folder(){
    if [ ! -d "${1}" ]; then
        mkdir ${1}
    fi
}
change_owner() {
    chown -R ${USER}:${GROUP} ${DOCHM}
}
line_insert(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    ADDNUM=${4:-0} 
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        LINENUM=$((${LINENUM}+${4}))
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}
install_wp_cli() {
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/bin/wp
    ln -s ${LSDIR}/${PHPVER}/bin/php /usr/bin/php
}
gen_password(){
    ROOT_PASS=$(cat ${HM_PATH}/.db_password | head -n 1 | awk -F '"' '{print $2}')
    WP_DB=$(echo "${MY_DOMAIN}" | sed -e 's/\.//g; s/-//g')
    WP_USER=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8; echo '')
    WP_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48; echo '')
}
install_wp() {
    if [ -e ${HM_PATH}/.db_password ]; then
        gen_password
        mysql -uroot -p${ROOT_PASS} -e "create database ${WP_DB};"
        if [ ${?} = 0 ]; then
            mysql -uroot -p${ROOT_PASS} -e "CREATE USER '${WP_USER}'@'localhost' IDENTIFIED BY '${WP_PASS}';"
            mysql -uroot -p${ROOT_PASS} -e "GRANT ALL PRIVILEGES ON * . * TO '${WP_USER}'@'localhost';"
            mysql -uroot -p${ROOT_PASS} -e "FLUSH PRIVILEGES;"
            rm -f ${DOCHM}/index.php
            if [ ! -f /usr/bin/wp ]; then
                install_wp_cli
            fi
            export WP_CLI_CACHE_DIR=${WWW_PATH}/.wp-cli/
            wp core download --path=${DOCHM} --allow-root --quiet
            wp core config --dbname=${WP_DB} --dbuser=${WP_USER} --dbpass=${WP_PASS} \
                --dbhost=localhost --dbprefix=wp_ --path=${DOCHM} --allow-root --quiet
            config_wp
            change_owner
            echoG "WP downloaded, please access your domain to complete the setup."
        else
            echoR "something went wrong when create new database, please proceed to manual installtion."
        fi
    else
        echoR "No DataBase Password, skip!"  
        show_help 3
    fi
}
config_wp() {
    echoG 'Setting WordPress'
    for PLUGIN in ${PLUGINLIST}; do
        echoG "Install ${PLUGIN}"
        wget -q -P ${DOCHM}/wp-content/plugins/ https://downloads.wordpress.org/plugin/${PLUGIN}
        if [ ${?} = 0 ]; then
            unzip -qq -o ${DOCHM}/wp-content/plugins/${PLUGIN} -d ${DOCHM}/wp-content/plugins/
        else
            echoR "${PLUGINLIST} FAILED to download"
        fi
    done
    rm -f ${DOCHM}/wp-content/plugins/*.zip
    create_file "${DOCHM}/.htaccess"
    cat <<EOM >${DOCHM}/.htaccess
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
    if [ ! -f ${DOCHM}/wp-content/themes/${THEME}/functions.php.bk ]; then
        cp ${DOCHM}/wp-content/themes/${THEME}/functions.php ${DOCHM}/wp-content/themes/${THEME}/functions.php.bk
        install_ed
        ed ${DOCHM}/wp-content/themes/${THEME}/functions.php <<END >>/dev/null 2>&1
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
}
check_install_wp() {
    if [ ${SILENT} = 'OFF' ]; then
        printf "%s" "Do you wish to install WordPress on this new domain? [y/N]: "
        read TMP_YN
    fi    
    if [[ "${TMP_YN}" =~ ^(y|Y) ]] || [ ${WORDPRESS} = 'ON' ]; then
        check_process 'mysqld'
        if [ ${?} = 0 ]; then
            if [ ! -f ${DOCHM}/wp-config.php ]; then
                install_wp
            else
                echoR 'WordPress existed, skip!'    
            fi    
        else
            echoR 'No MySQL environment, skip!'
        fi                
    fi
}
check_duplicate() {
    grep -w "${1}" ${2} >/dev/null 2>&1
}
restart_lsws(){
    ${LSDIR}/bin/lswsctrl restart >/dev/null
}   
set_vh_conf() {
    create_folder "${DOCHM}"
    create_folder "${VHDIR}/${MY_DOMAIN}"
    if [ ! -f "${DOCHM}/index.php" ]; then
        cat <<'EOF' >${DOCHM}/index.php
<?php
phpinfo();
EOF
        change_owner
    fi
    if [ ! -f "${VHDIR}/${MY_DOMAIN}/vhconf.conf" ]; then
        cat > ${VHDIR}/${MY_DOMAIN}/vhconf.conf << EOF
docRoot                   \$VH_ROOT
vhDomain                  \$VH_DOMAIN
vhAliases                 www.$VH_DOMAIN
adminEmails               localhost
enableGzip                1

errorlog $SERVER_ROOT/logs/$VH_NAME.error_log {
useServer               0
logLevel                ERROR
rollingSize             10M
}

accesslog $SERVER_ROOT/logs/$VH_NAME.access_log {
useServer               0
logFormat               "%v %h %l %u %t "%r" %>s %b"
logHeaders              5
rollingSize             10M
keepDays                10
}

index  {
useServer               0
indexFiles              index.php, index.html
}

scripthandler  {
add                     lsapi:${PHPVER} php
}

extprocessor ${PHPVER} {
type                    lsapi
address                 uds://tmp/lshttpd/${MY_DOMAIN}.sock
maxConns                35
env                     PHP_LSAPI_CHILDREN=35
initTimeout             60
retryTimeout            0
persistConn             1
respBuffer              0
autoStart               1
path                    ${LSDIR}/${PHPVER}/bin/lsphp
backlog                 100
instances               1
extUser                 ${USER}
extGroup                ${GROUP}
runOnStartUp            1
priority                0
memSoftLimit            2047M
memHardLimit            2047M
procSoftLimit           400
procHardLimit           500
}

rewrite  {
enable                  1
autoLoadHtaccess        1
}

vhssl  {
keyFile                 ${LSDIR}/conf/example.key
certFile                ${LSDIR}/conf/example.crt
certChain               1
}
EOF
        chown -R lsadm:lsadm ${VHDIR}/*
    else
        echoR "Targeted file already exist, skip!"
    fi
}
set_server_conf() {
    if [ ${WWW} = 'TRUE' ]; then
        NEWKEY="map                     ${MY_DOMAIN2} ${MY_DOMAIN}, ${MY_DOMAIN2}"
        local TEMP_DOMAIN=${MY_DOMAIN2}
    else
        NEWKEY="map                     ${MY_DOMAIN} ${MY_DOMAIN}"    
        local TEMP_DOMAIN=${MY_DOMAIN}
    fi
    PORT_ARR=$(grep "address.*:[0-9]"  ${WEBCF} | awk '{print substr($2,3)}')
    if [  ${#PORT_ARR[@]} != 0 ]; then
        for PORT in ${PORT_ARR[@]}; do 
            line_insert ":${PORT}$"  ${WEBCF} "${NEWKEY}" 2
        done
    else
        echoR 'No listener port detected, listener setup skip!'    
    fi
    echo "
virtualhost ${TEMP_DOMAIN} {
vhRoot                  ${WWW_PATH}/${MY_DOMAIN}
configFile              ${VHDIR}/${MY_DOMAIN}/vhconf.conf
allowSymbolLink         1
enableScript            1
restrained              1
}" >>${WEBCF}
}
update_vh_conf(){
    #replace user input email for locahost
    sed -i 's|localhost|'${EMAIL}'|g' ${VHDIR}/${MY_DOMAIN}/vhconf.conf
    sed -i 's|'${LSDIR}'/conf/example.key|/etc/letsencrypt/live/'${MY_DOMAIN}'/privkey.pem|g' ${VHDIR}/${MY_DOMAIN}/vhconf.conf
    sed -i 's|'${LSDIR}'/conf/example.crt|/etc/letsencrypt/live/'${MY_DOMAIN}'/fullchain.pem|g' ${VHDIR}/${MY_DOMAIN}/vhconf.conf
    echoG "\ncertificate has been successfully installed..."  
}
main_set_vh(){
    create_folder ${WWW_PATH}
    DOCHM="${WWW_PATH}/${1}"
    if [ ${DOMAIN_SKIP} = 'OFF' ]; then
        set_vh_conf
        set_server_conf
        restart_lsws
        echoG "Vhost created success!"
    fi    
}
verify_domain() {
    curl -Is http://${MY_DOMAIN}/ | grep -i LiteSpeed >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        echoG "${MY_DOMAIN} check PASS"
    else
        echoR "${MY_DOMAIN} inaccessible, skip!"
        DOMAIN_PASS='OFF'
    fi
    if [ ${WWW} = 'TRUE' ]; then
        curl -Is http://${MY_DOMAIN}/ | grep -i LiteSpeed >/dev/null 2>&1
        if [ ${?} = 0 ]; then
            echoG "${MY_DOMAIN2} check PASS"
        else
            echoR "${MY_DOMAIN2} inaccessible, skip!"
            DOMAIN_PASS='OFF'
        fi
    fi
}
input_email() {
    if [ ${SILENT} = 'OFF' ]; then
    	while true; do
            printf "%s" "Please enter your E-mail: "
            read EMAIL
            echoG "The E-mail you entered is: ${EMAIL}"
            printf "%s" "Please verify it is correct. [y/N]: "
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                break
            fi    
	    done
    fi
    if [[ ! ${EMAIL} =~ ${CKREG} ]]; then
    	echoR "\nPlease enter a valid E-mail, skip!\n"
        EMAIL_SKIP='ON'
    fi	
}
apply_lecert() {
    if [ ${WWW} = 'TRUE' ]; then
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} -d ${MY_DOMAIN2}
    else
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN}
    fi
    if [ ${?} -eq 0 ]; then
        update_vh_conf
    else
        echoR "Oops, something went wrong..."
        exit 1
    fi
}
hook_certbot() {
    sed -i 's/0.*/&  --deploy-hook "\/usr\/local\/lsws\/bin\/lswsctrl restart"/g' ${BOTCRON}
    check_duplicate 'restart' ${BOTCRON}
    if [ ${?} = 0 ]; then
        echoG 'Certbot hook update success'
    else
        echoY 'Please check certbot crond!'
    fi
}
force_https() {
    if [ ${SILENT} = 'OFF' ]; then
        printf "%s" "Do you wish to add a force https redirection rule? [y/N]: "
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
            FORCE_HTTPS='ON'
        fi  
    fi    
    if [ ${FORCE_HTTPS} = 'ON' ]; then
        create_file "${DOCHM}/.htaccess"
        check_duplicate 'https://' "${DOCHM}/.htaccess"   
        if [ ${?} = 1 ]; then
            echo "$(echo '
### Forcing HTTPS rule start
RewriteEngine On
RewriteCond %{SERVER_PORT} 80
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
### Forcing HTTPS rule end
            ' | cat - ${DOCHM}/.htaccess)" >${DOCHM}/.htaccess
            restart_lsws
            echoG "Force HTTPS rules added success!" 
        else
            echoR "Force HTTPS rules already existed, skip!"
        fi
    fi 
}
check_empty(){
    if [ -z "${1}" ]; then
        echoR "\nPlease input a value! exit!\n"
        exit 1
    fi
}
check_www_domain(){
    CHECK_WWW=$(echo "${1}" | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]]; then
        WWW='TRUE'
        MY_DOMAIN2=$(echo "${1}" | cut -c 5-)
    else
        MY_DOMAIN2="${1}"
    fi
}
domain_input(){
    if [ ${SILENT} = 'OFF' ]; then
        while true; do
            echo -e "Please enter your domain: e.g. www.domain.com or sub.domain.com"
            printf "%s" "Your domain: "
            read MY_DOMAIN
            echoG "The domain you put is: ${MY_DOMAIN}"
            printf "%s" "Please verify it is correct. [y/N]: "
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                break
            fi    
        done
    fi
    check_empty ${MY_DOMAIN}
    check_duplicate ${MY_DOMAIN} ${WEBCF}
    if [ ${?} = 0 ]; then
        echoR "domain existed, skip!"
        DOMAIN_SKIP='ON'
    fi
    check_www_domain ${MY_DOMAIN}
}
issue_cert(){
    if [ ${SILENT} = 'OFF' ]; then
        printf "%s" "Do you wish to issue a Let's encrypt certificate for this domain? [y/N]: "
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
            ISSUECERT='ON'
        fi  
    fi    
    if [ ${ISSUECERT} = 'ON' ]; then
        verify_domain
        if [ ${DOMAIN_PASS} = 'ON' ]; then
            input_email
            if [ ${EMAIL_SKIP} = 'OFF' ]; then
                apply_lecert
                hook_certbot
            fi    
        else
            show_help 2   
        fi    
    fi
}
main() {
    check_root
    check_provider
    check_home_path
    check_os
    domain_input
    main_set_vh ${MY_DOMAIN}
    issue_cert
    check_install_wp
    force_https
}

while [ ! -z "${1}" ]; do
    case $1 in
        -d | --domain) shift
            if [ "${1}" = '' ]; then
                show_help 1
            else
                MY_DOMAIN="${1}"
                SILENT='ON'
            fi
        ;;
        -le | --letsencrypt) shift
            if [ "${1}" = '' ] || [[ ! ${1} =~ ${CKREG} ]]; then
                echoR "\nPlease enter a valid E-mail, exit!\n"   
                exit 1
            else
                ISSUECERT='ON'
                EMAIL="${1}"
            fi
        ;;
        -f | --force-https)
            FORCE_HTTPS='ON'
        ;;
        -h | --help)
            show_help 1
        ;;
        -w | --wordpress)
            WORDPRESS='ON'
        ;;
        *)
            echoR "unknown argument..."
            show_help 1
        ;;
    esac
    shift
done
main
echoG 'Setup finished!'
exit 0