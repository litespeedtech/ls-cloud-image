#!/bin/bash
# /********************************************************************
# LiteSpeed domain setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2023
# @Version: 2.3
# *********************************************************************/
MY_DOMAIN=''
MY_DOMAIN2=''
WWW_PATH='/var/www'
CUSTOM_PATH=''
LSDIR='/usr/local/lsws'
WEBCF="${LSDIR}/conf/httpd_config.conf"
VHDIR="${LSDIR}/conf/vhosts"
EMAIL='localhost'
WWW='FALSE'
BACKUP='OFF'
BOTCRON='/etc/cron.d/certbot'
PLUGINLIST="litespeed-cache.zip"
CKREG="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*\
@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
THEME='twentytwenty'
PHPVER=lsphp74
WEBSERVER='OLS'
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
CLASSICPRESS='OFF'
DB_TEST=0
EPACE='        '

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
echow(){
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}

show_help() {
    case ${1} in
    "1")
        echo -e "\033[1mOPTIONS\033[0m"
        echow "-D, --domain [DOMAIN_NAME]"
        echo "${EPACE}${EPACE}If you wish to add www domain , please attach domain with www"
        echow "-LE, --letsencrypt [EMAIL]"
        echo "${EPACE}${EPACE}Issue let's ecnrypt certificate, must follow with E-mail address."
        echow "-F, --force-https"
        echo "${EPACE}${EPACE}This will add a force HTTPS rule in htaccess file"
        echow "-W, --wordpress"
        echo "${EPACE}${EPACE}This will install a Wordpress with LiteSpeed Cache plugin."
        echo "${EPACE}${EPACE}Example: ./vhsetup.sh -d www.example.com -le admin@example.com -f -w"
        echo "${EPACE}${EPACE}Above example will create a virtual host with www.example.com and example.com domain"
        echo "${EPACE}${EPACE}Issue and install Let's encrypt certificate and Wordpress with LiteSpeed Cache plugin."
        echow "-C, --classicpress"
        echo "${EPACE}${EPACE}This will install a ClassicPress with LiteSpeed Cache plugin."   
        echow "--path, --document-path [CUSTOM_PATH]"
        echo "${EPACE}${EPACE}This is to specify a location for the document root."  
        echo "${EPACE}${EPACE}Example: ./vhsetup.sh --path /var/www/html"        
        echow "-BK, --backup"
        echo "${EPACE}${EPACE}This will backup the lsws server config before changing anything, vhost config is not included."
        echow "--delete [DOMAIN_NAME]"
        echo "${EPACE}${EPACE}This will remove the domain from listener and virtual host config, the document root will remain."
        echow '-H, --help'
        echo "${EPACE}${EPACE}Display help and exit."
        exit 0
    ;;    
    "2")
        echoY "If you need to install cert manually later, please check:" 
        echoB "https://docs.litespeedtech.com/shared/cloud/OPT-LETSHTTPS/"
        echo ''
    ;;  
    "3")
        echo "Please make sure you have ${HM_PATH}/.db_password file with content:"
        echoY 'root_mysql_pass="YOUR_DB_PASSWORD"'
    ;;  
    esac
}

function check_os
{
    if [ -f /etc/centos-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
        case $(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1) in 
        6)
            OSNAMEVER=CENTOS6
            OSVER=6
            ;;
        7)
            OSNAMEVER=CENTOS7
            OSVER=7
            ;;
        8)
            OSNAMEVER=CENTOS8
            OSVER=8
            ;;
        9)
            OSNAMEVER=CENTOS9
            OSVER=9
            ;;            
        esac
    elif [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
        case $(cat /etc/redhat-release | tr -dc '0-9.'|cut -d \. -f1) in 
        6)
            OSNAMEVER=CENTOS6
            OSVER=6
            ;;
        7)
            OSNAMEVER=CENTOS7
            OSVER=7
            ;;
        8)
            OSNAMEVER=CENTOS8
            OSVER=8
            ;;
        9)
            OSNAMEVER=CENTOS9
            OSVER=9
            ;;            
        esac             
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        case $(cat /etc/os-release | grep UBUNTU_CODENAME | cut -d = -f 2) in
        trusty)
            OSNAMEVER=UBUNTU14
            OSVER=trusty
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
            ;;        
        xenial)
            OSNAMEVER=UBUNTU16
            OSVER=xenial
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
            ;;
        bionic)
            OSNAMEVER=UBUNTU18
            OSVER=bionic
            MARIADBCPUARCH="arch=amd64"
            ;;
        focal)            
            OSNAMEVER=UBUNTU20
            OSVER=focal
            MARIADBCPUARCH="arch=amd64"
            ;;
        jammy)            
            OSNAMEVER=UBUNTU22
            OSVER=jammy
            MARIADBCPUARCH="arch=amd64"
            ;;            
        esac
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        case $(cat /etc/os-release | grep VERSION_CODENAME | cut -d = -f 2) in
        jessie)
            OSNAMEVER=DEBIAN8
            OSVER=jessie
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        stretch) 
            OSNAMEVER=DEBIAN9
            OSVER=stretch
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        buster)
            OSNAMEVER=DEBIAN10
            OSVER=buster
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        bullseye)
            OSNAMEVER=DEBIAN11
            OSVER=bullseye
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        esac    
    fi

    if [ "$OSNAMEVER" = '' ] ; then
        echoR "Sorry, currently one click installation only supports Centos(6-8), Debian(8-11) and Ubuntu(14,16,18,20,22)."
        echoR "You can download the source code and build from it."
        echoR "The url of the source code is https://github.com/litespeedtech/openlitespeed/releases."
        exit 1
    else
        if [ "$OSNAME" = "centos" ] ; then
            echoG "Current platform is "  "$OSNAME $OSVER."
        else
            export DEBIAN_FRONTEND=noninteractive
            echoG "Current platform is "  "$OSNAMEVER $OSNAME $OSVER."
        fi
    fi
}    

check_provider()
{
    if [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then 
        PROVIDER='aws'
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'
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
check_home_path()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
        HM_PATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
        HM_PATH='/home/ubuntu'  
    elif [ ${PROVIDER} = 'aliyun' ] && [ -d /home/ubuntu ]; then
        HM_PATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'oracle' ] && [ -d /home/ubuntu ]; then
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
check_php_version(){
    PHP_MA="$(php -r 'echo PHP_MAJOR_VERSION;')"
    PHP_MI="$(php -r 'echo PHP_MINOR_VERSION;')"
    if [ -e ${LSDIR}/lsphp${PHP_MA}${PHP_MI}/bin/php ]; then
        PHPVER="lsphp${PHP_MA}${PHP_MI}"
    fi
}

check_webserver(){
    if [ -e ${LSDIR}/bin/openlitespeed ]; then
        if [ -e "${WEBCF}" ]; then
            WEBSERVER='OLS'
            VH_CONF_FILE="${VHDIR}/${MY_DOMAIN}/vhconf.conf"
        else
            echoR "${WEBCF} does not exist, exit!"
            exit 1  
        fi
    else 
        if [ -e "${LSDIR}/conf/httpd_config.xml" ]; then
            WEBSERVER='LSWS'
            WEBCF="${LSDIR}/conf/httpd_config.xml"
            VH_CONF_FILE="${VHDIR}/${MY_DOMAIN}/vhconf.xml"
        else 
            echoR 'No web serevr detect, exit!'
            exit 2
        fi
    fi    
}

fst_match_line(){
    FIRST_LINE_NUM=$(grep -n -m 1 "${1}" "${2}" | awk -F ':' '{print $1}')
}
fst_match_before(){
    FIRST_NUM_BEFORE=$(grep -B 5 ${1} ${2} | grep -n -m 1 ${3} | awk -F ':' '{print $1}')
}
fst_match_before_line(){
    fst_match_before ${1} ${2} ${3}
    FIRST_BEFORE_LINE_NUM=$((${FIRST_LINE_NUM}+${FIRST_NUM_BEFORE}-1))
}
fst_match_after(){
    FIRST_NUM_AFTER=$(tail -n +${1} ${2} | grep -n -m 1 ${3} | awk -F ':' '{print $1}')
}
lst_match_line(){
    fst_match_after ${1} ${2} ${3}
    LAST_LINE_NUM=$((${FIRST_LINE_NUM}+${FIRST_NUM_AFTER}-1))
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
        mkdir -p ${1}
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
    if [ ! -e /usr/local/bin/wp ]; then
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi    
    if [ ! -f /usr/bin/php ]; then
        if [ -e ${LSDIR}/${PHPVER}/bin/php ]; then
            ln -s ${LSDIR}/${PHPVER}/bin/php /usr/bin/php
        else
            echoR "${LSDIR}/${PHPVER}/bin/php not exist, please check your PHP version!"
            exit 1 
        fi        
    fi      
}
ubuntu_install_certbot(){       
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

centos_install_certbot(){
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

install_certbot(){
    if [ ! -e /usr/bin/certbot ] && [ ! -e /usr/local/bin/certbot ]; then
        echoG "Install CertBot" 
        if [ ${OSNAME} = 'centos' ]; then
            centos_install_certbot
        else
            ubuntu_install_certbot 
        fi
    fi
}

install_unzip(){
    if [ ! -e /usr/bin/unzip ]; then
        echoG "Install unzip" 
        if [ ${OSNAME} = 'centos' ]; then
            yum install unzip -y > /dev/null 2>&1
        else
            apt install unzip -y > /dev/null 2>&1
        fi
    fi    
}

gen_password(){
    if [ -e ${HM_PATH}/.db_password ]; then
        ROOT_PASS=$(cat ${HM_PATH}/.db_password | head -n 1 | awk -F '"' '{print $2}')
    fi    
    WP_DB=$(echo "${MY_DOMAIN}" | sed -e 's/\.//g; s/-//g')
    WP_USER=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8; echo '')
    WP_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48; echo '')
}

check_which_cms(){
    if [ ${SILENT} = 'OFF' ]; then
		while true; do
			echo -e "Please choose whether to install WordPress or ClassicPress"
            if [ "${WORDPRESS}" = 'OFF' ] && [ "${CLASSICPRESS}" = 'OFF' ]; then
                printf "%s" "Install WordPress? [y/N]: "
                read TMP_YN
                if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                    WORDPRESS='ON'
                else
                    WORDPRESS='OFF'    
                fi
            fi
            if [ "${WORDPRESS}" = 'OFF' ] && [ "${CLASSICPRESS}" = 'OFF' ]; then 
                printf "%s" "Install ClassicPress? [y/N]: "
                read TMP_YN
                if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                    CLASSICPRESS='ON'
                else
                    CLASSICPRESS='OFF'    
                fi
            fi
            if [ "${WORDPRESS}" = 'ON' ]; then
                printf "%s" "The Application you input is WordPress. [y/N]: "
            elif [ "${CLASSICPRESS}" = 'ON' ]; then
                printf "%s" "The Application you input is ClassicPress. [y/N]: "
            else
                printf "%s" "The Application you input is None. [y/N]: "
            fi
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                break
            else
                WORDPRESS='OFF'
                CLASSICPRESS='OFF'
            fi
		done
	fi
}

get_theme_name(){
    THEME_NAME=$(grep WP_DEFAULT_THEME ${DOCHM}/wp-includes/default-constants.php | grep -v '!' | awk -F "'" '{print $4}')
    echo "${THEME_NAME}" | grep 'twenty' >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        THEME="${THEME_NAME}"
    fi
}

install_wp_plugin(){
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
}

set_lscache(){
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

create_db_user(){
    if [ -e ${HM_PATH}/.db_password ]; then
        gen_password
        mysql -uroot -p${ROOT_PASS} -e "create database ${WP_DB};"
        if [ ${?} = 0 ]; then
            mysql -uroot -p${ROOT_PASS} -e "CREATE USER '${WP_USER}'@'localhost' IDENTIFIED BY '${WP_PASS}';"
            mysql -uroot -p${ROOT_PASS} -e "GRANT ALL PRIVILEGES ON * . * TO '${WP_USER}'@'localhost';"
            mysql -uroot -p${ROOT_PASS} -e "FLUSH PRIVILEGES;"
        else
            echoR "something went wrong when create new database, please proceed to manual installtion."
            DB_TEST=1
        fi
    elif [ -e /usr/local/lsws/password ]; then
        grep mysql /usr/local/lsws/password | grep root | awk -F'[][]' '{print $2}'  >/dev/null
        if [ ${?} = 0 ]; then
            echoG 'Found SQL password in /usr/local/lsws/password file.'
            ROOT_PASS=$(grep mysql /usr/local/lsws/password | grep root | awk -F'[][]' '{print $2}')
            gen_password
            mysql -uroot -p${ROOT_PASS} -e "create database ${WP_DB};"
            if [ ${?} = 0 ]; then
                mysql -uroot -p${ROOT_PASS} -e "CREATE USER '${WP_USER}'@'localhost' IDENTIFIED BY '${WP_PASS}';"
                mysql -uroot -p${ROOT_PASS} -e "GRANT ALL PRIVILEGES ON * . * TO '${WP_USER}'@'localhost';"
                mysql -uroot -p${ROOT_PASS} -e "FLUSH PRIVILEGES;"
            else
                echoR "something went wrong when create new database, please proceed to manual installtion."
                DB_TEST=1
            fi            
        else
            echoR "No DataBase Password, skip!"  
            DB_TEST=1
            show_help 3
        fi    
    else
        echoR "No DataBase Password, skip!"  
        DB_TEST=1
        show_help 3
    fi    
}

install_wp() {
    create_db_user
    if [ ${DB_TEST} = 0 ]; then
        install_wp_cli
        rm -f ${DOCHM}/index.php
        export WP_CLI_CACHE_DIR=${WWW_PATH}/.wp-cli/
        wp core download --path=${DOCHM} --allow-root --quiet
        wp core config --dbname=${WP_DB} --dbuser=${WP_USER} --dbpass=${WP_PASS} \
            --dbhost=localhost --dbprefix=wp_ --path=${DOCHM} --allow-root --quiet
        get_theme_name
        config_wp
        change_owner
        echoG "WP downloaded, please access your domain to complete the setup."    
    fi
}

set_wp_htaccess(){
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
}

config_wp() {
    echoG 'Setting WordPress'
    install_wp_plugin
    set_wp_htaccess
    set_lscache
    echoG 'Finish WordPress'
}

check_install_wp() { 
    if [ ${WORDPRESS} = 'ON' ]; then
        check_process 'mysqld\|mariadb'
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

install_cp() {
    create_db_user
    if [ ${DB_TEST} = 0 ]; then
        install_wp_cli
        export WP_CLI_CACHE_DIR=${WWW_PATH}/.wp-cli/
        cd ${DOCHM}
        wget -q --no-check-certificate https://www.classicpress.net/latest.tar.gz -O classicpress.tar.gz
        tar -xzvf classicpress.tar.gz --strip-components=1 -C ${DOCHM}  >/dev/null 2>&1
        rm -rf classicpress.tar.gz
        wp core config --dbname=${WP_DB} --dbuser=${WP_USER} --dbpass=${WP_PASS} \
            --dbhost=localhost --dbprefix=cp_ --path=${DOCHM} --allow-root --quiet
        get_theme_name
        config_cp
        change_owner
        echoG "ClassicPress downloaded, please access your domain to complete the setup." 
    fi    
}

set_cp_htaccess(){
    create_file "${DOCHM}/.htaccess"
    cat <<EOM >${DOCHM}/.htaccess
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

config_cp() {
    echoG 'Setting ClassicPress'
    install_wp_plugin
    set_cp_htaccess
    set_lscache
    echoG 'Finish ClassicPress'
}

check_install_cp() {
    if [ "${CLASSICPRESS}" = 'ON' ]; then
        check_process 'mysqld\|mariadb'
        if [ ${?} = 0 ]; then
            if [ ! -f ${DOCHM}/wp-config.php ]; then
                install_cp
            else
                echoR "ClassicPress already exists at ${DOCHM}. Skip!"   
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
    systemctl restart lsws >/dev/null 2>&1
}

set_ols_vh_conf() {
    create_folder "${DOCHM}"
    create_folder "${VHDIR}/${MY_DOMAIN}"
    if [ ! -f "${DOCHM}/index.php" ]; then
        cat <<'EOF' >${DOCHM}/index.php
<?php
phpinfo();
EOF
        change_owner
    fi
    if [ ! -f "${VH_CONF_FILE}" ]; then
        cat > ${VH_CONF_FILE} << EOF
docRoot                   \$VH_ROOT
vhDomain                  \$VH_DOMAIN
vhAliases                 www.$VH_DOMAIN
adminEmails               localhost@example
enableGzip                1

errorlog \$SERVER_ROOT/logs/\$VH_NAME.error_log {
useServer               0
logLevel                ERROR
rollingSize             10M
}

accesslog \$SERVER_ROOT/logs/\$VH_NAME.access_log {
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

set_lsws_vh_conf() {
    create_folder "${DOCHM}"
    create_folder "${VHDIR}/${MY_DOMAIN}"
    if [ ! -f "${DOCHM}/index.php" ]; then
        cat <<'EOF' >${DOCHM}/index.php
<?php
phpinfo();
EOF
        change_owner
    fi
    if [ ! -f "${VH_CONF_FILE}" ]; then
        cat > ${VH_CONF_FILE} << EOF
<?xml version="1.0" encoding="UTF-8"?>
<virtualHostConfig>
  <docRoot>\$VH_ROOT</docRoot>
  <vhDomain>$VH_DOMAIN</vhDomain>
  <adminEmails>localhost</adminEmails>
  <index>
    <useServer>0</useServer>
    <indexFiles>index.php, index.html</indexFiles>
  </index>
  <rewrite>
    <enable>1</enable>
    <autoLoadHtaccess>1</autoLoadHtaccess>
  </rewrite>
  <vhssl>
    <keyFile>${LSDIR}/conf/example.key</keyFile>
    <certFile>${LSDIR}/conf/example.crt</certFile>
    <certChain>1</certChain>
  </vhssl>
</virtualHostConfig>
EOF
        chown -R lsadm:lsadm ${VHDIR}/*
    else
        echoR "Targeted file already exist, skip!"
    fi
}


set_ols_server_conf() {
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
    if [ "${CUSTOM_PATH}" = '' ]; then
        CUSTOM_PATH="${WWW_PATH}/${MY_DOMAIN}"
    fi    
    echo "
virtualhost ${TEMP_DOMAIN} {
vhRoot                  "${CUSTOM_PATH}"
configFile              ${VH_CONF_FILE}
allowSymbolLink         1
enableScript            1
restrained              1
}" >>${WEBCF}
}

update_ssl_vh_conf(){
    sed -i 's|localhost|'${EMAIL}'|g' ${VH_CONF_FILE}
    sed -i 's|'${LSDIR}'/conf/example.key|/etc/letsencrypt/live/'${MY_DOMAIN}'/privkey.pem|g' ${VH_CONF_FILE}
    sed -i 's|'${LSDIR}'/conf/example.crt|/etc/letsencrypt/live/'${MY_DOMAIN}'/fullchain.pem|g' ${VH_CONF_FILE}
    echoG "\ncertificate has been successfully installed..."  
}

set_lsws_server_conf(){
    if [ ${WWW} = 'TRUE' ]; then
        NEWKEY="\\
      <vhostMap>\n\
          <vhost>${MY_DOMAIN2}</vhost>\n\
          <domain>${MY_DOMAIN2}, ${MY_DOMAIN}</domain>\n\
      </vhostMap>"
        local TEMP_DOMAIN=${MY_DOMAIN2}
    else
        NEWKEY="\\
      <vhostMap>\n\
          <vhost>${MY_DOMAIN}</vhost>\n\
          <domain>${MY_DOMAIN}</domain>\n\
      </vhostMap>"
        local TEMP_DOMAIN=${MY_DOMAIN}
    fi
    MATCH_ARR=$(grep -n '<vhostMapList>' ${WEBCF} | cut -f1 -d: | sort -nr)
    if [ ${#MATCH_ARR[@]} != 0 ]; then
        for LINENUM in ${MATCH_ARR[@]}; do
            LINENUM=$((${LINENUM}+1))
            sed -i "${LINENUM}i${NEWKEY}" ${WEBCF}
        done
    else
        echoR 'No listener port detected, listener setup skip!'    
    fi

    if [ "${CUSTOM_PATH}" = '' ]; then
        CUSTOM_PATH="${WWW_PATH}/${MY_DOMAIN}"
    fi

   NEWKEY=" \\
    <virtualHost>\n\
      <name>${TEMP_DOMAIN}</name>\n\
      <vhRoot>"${CUSTOM_PATH}"</vhRoot>\n\
      <configFile>${VH_CONF_FILE}</configFile>\n\
      <allowSymbolLink>1</allowSymbolLink>\n\
      <enableScript>1</enableScript>\n\
      <restrained>0</restrained>\n\
    </virtualHost>"

    line_insert '<virtualHostList>'  ${WEBCF} "${NEWKEY}" 1
}


main_set_vh(){
    create_folder ${WWW_PATH}
    if [ "${CUSTOM_PATH}" = '' ]; then
        DOCHM="${WWW_PATH}/${1}"
    else
        DOCHM="${CUSTOM_PATH}"
        create_folder ${CUSTOM_PATH}
    fi    
    if [ ${DOMAIN_SKIP} = 'OFF' ]; then
        if [ "${WEBSERVER}" = 'OLS' ]; then
            set_ols_vh_conf
            set_ols_server_conf
        elif [ "${WEBSERVER}" = 'LSWS' ]; then
            set_lsws_vh_conf
            set_lsws_server_conf
        fi            
        restart_lsws
        echoG "Vhost created success!"
    fi    
}

rm_ols_vh_conf(){
    if [ -f "${VH_CONF_FILE}" ]; then
        echoG "Remove virtual host config: ${VHDIR}/${MY_DOMAIN}"
        rm -rf "${VHDIR}/${MY_DOMAIN}"
    elif [ -f "${VHDIR}/${MY_DOMAIN2}/vhconf.conf" ]; then
        echoG "Remove virtual host config: ${VHDIR}/${MY_DOMAIN2}"
        rm -rf "${VHDIR}/${MY_DOMAIN2}"
    elif [ -f "${VHDIR}/www.${MY_DOMAIN}/vhconf.conf" ]; then
        echoG "Remove virtual host config: ${VHDIR}/www.${MY_DOMAIN}"
        rm -rf "${VHDIR}/www.${MY_DOMAIN}"
    else
        echoR "${VH_CONF_FILE} does not exist, skip!" 
    fi
}

rm_dm_ols_svr_conf(){
    echoG 'Remove domain from listeners'
    sed -i "/map.*${1}/d" ${WEBCF}
    grep "virtualhost ${1}" ${WEBCF} >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        fst_match_line "virtualhost ${1}" ${WEBCF}
        lst_match_line ${FIRST_LINE_NUM} ${WEBCF} '}'
        echoG 'Remove the virtual host from serevr config'
        sed -i "${FIRST_LINE_NUM},${LAST_LINE_NUM}d" ${WEBCF}
    else
        echoR "virtualhost ${1} does not found, if this is the default virtual host config, please remove it manually!"
    fi    
}

rm_lsws_vh_conf(){
    if [ -f "${VH_CONF_FILE}" ]; then
        echoG "Remove virtual host config: ${VHDIR}/${MY_DOMAIN}"
        rm -rf "${VHDIR}/${MY_DOMAIN}"
    elif [ -f "${VHDIR}/${MY_DOMAIN2}/vhconf.xml" ]; then
        echoG "Remove virtual host config: ${VHDIR}/${MY_DOMAIN2}"
        rm -rf "${VHDIR}/${MY_DOMAIN2}"
    elif [ -f "${VHDIR}/www.${MY_DOMAIN}/vhconf.xml" ]; then
        echoG "Remove virtual host config: ${VHDIR}/www.${MY_DOMAIN}"
        rm -rf "${VHDIR}/www.${MY_DOMAIN}"
    else
        echoR "${VH_CONF_FILE} does not exist, skip!" 
    fi
}

rm_dm_lsws_svr_conf(){
    echoY 'Remove LSWS VirtualHost does not support yet!' 
}

rm_le_cert(){
    echoG 'Remove Lets Encrypt Certificate'
    certbot delete --cert-name ${MY_DOMAIN} >/dev/null 2>&1
    certbot delete --cert-name ${MY_DOMAIN2} >/dev/null 2>&1
}

rm_main_conf(){

    if [ "${WEBSERVER}" = 'OLS' ]; then
        grep -w "map.*[[:space:]]${MY_DOMAIN}" ${WEBCF} >/dev/null 2>&1
        if [ ${?} = 0 ]; then
            echoG "Domain exist, continue deleting.."        
            rm_ols_vh_conf
            rm_dm_ols_svr_conf ${MY_DOMAIN2}
            restart_lsws
            echoG "Domain remove finished!"
        else 
            echoR "Domain does not exist, exit!"  
            exit 1       
        fi     
    elif [ "${WEBSERVER}" = 'LSWS' ]; then
        grep -w "<vhost>${MY_DOMAIN}" ${WEBCF} >/dev/null 2>&1
        if [ ${?} = 0 ]; then
            echoG "Domain exist, continue deleting.." 
            rm_lsws_vh_conf
            rm_dm_lsws_svr_conf ${MY_DOMAIN2}
            restart_lsws
            echoG "Domain remove finished!"
        else 
            echoR "Domain does not exist, exit!"  
            exit 1       
        fi
    fi


}

verify_domain() {
    curl -Is http://${MY_DOMAIN}/ | grep -i 'LiteSpeed\|cloudflare' >/dev/null 2>&1
    if [ ${?} = 0 ]; then
        echoG "${MY_DOMAIN} check PASS"
    else
        echoR "${MY_DOMAIN} inaccessible, skip!"
        DOMAIN_PASS='OFF'
    fi
    if [ ${WWW} = 'TRUE' ]; then
        curl -Is http://${MY_DOMAIN}/ | grep -i 'LiteSpeed\|cloudflare' >/dev/null 2>&1
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
        update_ssl_vh_conf    
    else
        echoR "Oops, something went wrong..."
        exit 1
    fi
}

certbothook() {
    grep 'certbot.*restart lsws' ${BOTCRON} >/dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG 'Web Server Restart hook already set!'
    else
        if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ] ; then
            sed -i 's/0.*/&  --deploy-hook "systemctl restart lsws"/g' ${BOTCRON}
        elif [ "${OSNAME}" = 'centos' ]; then
            if [ "${OSVER}" = '7' ]; then
                echo "0 0,12 * * * root python -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q --deploy-hook 'systemctl restart lsws'" \
                | sudo tee -a /etc/crontab > /dev/null
            elif [ "${OSVER}" = '8' ]; then
                echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && /usr/local/bin/certbot renew -q --deploy-hook 'systemctl restart lsws'" \
                | sudo tee -a /etc/crontab > /dev/null
            else
                echoY 'Please check certbot crontab'
            fi
        fi    
        grep 'restart lsws' ${BOTCRON} > /dev/null 2>&1
        if [ ${?} = 0 ]; then 
            echoG 'Certbot hook update success'
        else 
            echoY 'Please check certbot crond'
        fi
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

server_conf_bk(){
    if [ "${BACKUP}" = 'ON' ]; then
        local TIME_VER=$(date +%s)
        echoG "Back up server config to ${WEBCF}.${TIME_VER}"
        if [ ! -f ${WEBCF}.${TIME_VER} ]; then
            cp "${WEBCF}" "${WEBCF}.${TIME_VER}"
        fi
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
                install_certbot
                apply_lecert
                certbothook
                restart_lsws
            fi    
        else
            show_help 2   
        fi    
    fi
}

end_msg(){
    echoG 'Setup finished!'
}    

main() {
    check_root
    check_provider
    check_home_path
    check_os
    check_php_version
    domain_input
    check_webserver
    server_conf_bk    
    main_set_vh ${MY_DOMAIN}
    issue_cert
    install_unzip
	check_which_cms
    check_install_wp
	check_install_cp
    force_https
    end_msg
}

main_delete(){
    check_webserver
    check_empty ${1}
    check_www_domain ${1}
    server_conf_bk
    rm_le_cert
    rm_main_conf
}

while [ ! -z "${1}" ]; do
    case $1 in
        -[dD] | --domain) shift
            if [ "${1}" = '' ]; then
                show_help 1
            else
                MY_DOMAIN="${1}"
                SILENT='ON'
            fi
        ;;
        -le | -LE | --letsencrypt) shift
            if [ "${1}" = '' ] || [[ ! ${1} =~ ${CKREG} ]]; then
                echoR "\nPlease enter a valid E-mail, exit!\n"   
                exit 1
            else
                ISSUECERT='ON'
                EMAIL="${1}"
            fi
        ;;
        -[fF] | --force-https)
            FORCE_HTTPS='ON'
        ;;
        -BK | --backup)
            BACKUP='ON'
        ;;    
        -[hH] | --help)
            show_help 1
        ;;
        -[wW] | --wordpress)
            WORDPRESS='ON'
        ;;
        -[cC] | --classicpress)
            CLASSICPRESS='ON'
        ;;
        --path | --document-path) shift
            if [ "${1}" = '' ]; then
                show_help 1
            else
                CUSTOM_PATH="${1}"
                SILENT='ON'
            fi
        ;;
        --delete) shift
            if [ "${1}" = '' ]; then
                show_help 1
            else
                MY_DOMAIN="${1}"
                main_delete "${MY_DOMAIN}"
                exit 0
            fi
        ;;             
        *)
            echoR "unknown argument..."
            show_help 1
        ;;
    esac
    shift
done
main
exit 0