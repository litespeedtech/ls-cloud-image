#!/usr/bin/env bash
# /********************************************************************
# OpenLiteSpeed to Enterprise setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Version: 2.1
# *********************************************************************/
TOTAL_RAM=$(free -m | awk '/Mem:/ { print $2 }')
LICENSE_KEY=""
PHP='php'
ADMIN_PASS='12345678'
PANEL=''
LS_DIR='/usr/local/lsws'
STORE_DIR='/opt/.litespeed_conf'
ols_conf_file="${LS_DIR}/conf/httpd_config.conf"
CONVERT_LOG='/opt/convert.log'
declare -a vhosts
declare -a domains
EPACE='        '
start_mark='{'
end_mark='}'

echow(){
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}
echoR()
{
    echo -e "\033[38;5;203m${1}\033[39m"
}

show_help() {
    echo -e "\nOpenLiteSpeed to LiteSpeed Enterprise converter script."
    echo -e "\nThis script will:"
    echo -e "1. Generate LSWS config file from OpenLiteSpeed."
    echo -e "2. Ask you to input valid license key or Trial."
    echo -e "3. Backup current ${LS_DIR}/conf directory to ${STORE_DIR} and uninstall OpenLiteSpeed"
    echo -e "4. Install LiteSpeed Enterprise and use the configuration file from step 1\n"
    echo -e "\033[1m[Options]\033[0m"
    echow '-L, --lsws'
    echo "${EPACE}${EPACE} Install and switch from OLS to LSWS. "
    echow '-R, --restore'
    echo "${EPACE}${EPACE} Restore to OpenLiteSpeed. "    
    echow '-H, --help'
    echo "${EPACE}${EPACE}Display help and exit."
    exit 0
}

webadmin_reset() {
    echoG 'Set webadmin password.'
    if [[ -f ${LS_DIR}/admin/fcgi-bin/admin_php ]] ; then
  	    php_command="admin_php"
    else
  	    php_command="admin_php5"
    fi
    if [ -e /root/.litespeed_password ]; then
        WEBADMIN_PASS=$(awk -F '=' '{print $2}' /root/.litespeed_password)
    elif [ -e /home/ubuntu/.litespeed_password ]; then
        WEBADMIN_PASS=$(awk -F '=' '{print $2}' /home/ubuntu/.litespeed_password)
    else    
        WEBADMIN_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi    
    TEMP=`${LS_DIR}/admin/fcgi-bin/${php_command} ${LS_DIR}/admin/misc/htpasswd.php ${WEBADMIN_PASS}`
    echo "" > ${LS_DIR}/admin/conf/htpasswd
    echo "admin:$TEMP" > ${LS_DIR}/admin/conf/htpasswd
    echoG "WebAdmin Console password has been set to: ${WEBADMIN_PASS}"
}

check_no_panel(){
    if [ -d /usr/local/CyberCP ]; then
        PANEL='cyberpanel'
    elif [ -d /usr/local/cpanel ]; then
        PANEL='cpanel'
    elif [ -d /usr/local/plesk ]; then
        PANEL='plesk'
    elif [ -d /usr/local/directadmin ]; then
        PANEL='directadmin'
    fi
    if [ ! -z "${PANEL}" ]; then
        echoR "Detect control panel: ${PANEL}, exit!"; exit 1 
    fi 
}


check_pkg_manage(){
    if hash apt > /dev/null 2>&1 ; then
        PKG_TOOL='apt'
        USER="www-data"
        GROUP="www-data"      
    elif hash yum > /dev/null 2>&1 ; then
        PKG_TOOL='yum'
        USER="nobody"
        GROUP="nobody"      
    else
      echoR 'can not detect package management tool ...'
      exit 1
    fi
}

check_php(){
    if [ -e ${LS_DIR}/lsphp73/bin/php ]; then
        PHP="${LS_DIR}/lsphp73/bin/php"
    elif [ -e ${LS_DIR}/lsphp74/bin/php ]; then
        PHP="${LS_DIR}/lsphp74/bin/php"
    elif [ -e ${LS_DIR}/lsphp81/bin/php ]; then
        PHP="${LS_DIR}/lsphp81/bin/php"        
    fi  
    which ${PHP} >/dev/null
    if [ ${?} = 0 ]; then
        echoG 'PHP path exist'
    else
        ls ${LS_DIR}/lsphp* >/dev/null
        if [ ${?} = 0 ]; then
            echoG 'PHP path update' 
            PHP=$(find ${LS_DIR}/lsphp* -path \*bin/php | head -n 1)
        fi
        which ${PHP} >/dev/null
        if [ ${?} != 0 ]; then
            echoR 'PHP path does not exist, exit!'; exit 1
        fi
    fi
}

add_converter_script(){
cat << EOM > ${LS_DIR}/admin/misc/converter.php
<?php
\$lsws = dirname(dirname(__DIR__)) . '/';
ini_set('include_path',
        \$lsws . 'admin/html/lib/:' .
        \$lsws . 'admin/html/lib/ows/:' .
        \$lsws . 'admin/html/view/');
date_default_timezone_set('America/New_York');
spl_autoload_register( function (\$class) {
        include \$class . '.php';
});
CData::Util_Migrate_AllConf2Xml(\$lsws);
EOM
    chmod +x ${LS_DIR}/admin/misc/converter.php
}

gen_ent_config(){
    if [ ! -e "${LS_DIR}/admin/misc/converter.php" ]; then
        echo "${LS_DIR}/admin/misc/converter.php not exist, exit!"
        exit 1
    fi
    if [ ! -e "${LS_DIR}/bin/openlitespeed" ]; then
        echo 'OpenLiteSpeed does not exist, exit!'
        exit 1
    fi
    ${PHP} ${LS_DIR}/admin/misc/converter.php 2>${CONVERT_LOG}
    if [ ${?} != 0 ]; then 
        echo "Convert config file failed, error code: ${?}"
        echoR "#############################################"
        cat ${CONVERT_LOG}
        echoR "#############################################"
        exit 1
    fi
    CONVERTFOLD=($(awk '/converted/ {print $2}' ${CONVERT_LOG} | awk -F '/' 'NF-=1' OFS="/"))
    CONVERTPATH=($(awk '/converted/ {print $2}' ${CONVERT_LOG}))
    CONVERTFILE=($(awk '/converted/ {print $2}' ${CONVERT_LOG} | awk -F '/' '{print $NF}'))

    for FOLDER in "${CONVERTFOLD[@]}"; do
        VNAME=$(echo ${FOLDER} | awk -F '/' '$6 == "vhosts" {print $7}')
        if [ ! -z "${VNAME}" ]; then
            mkdir -p ${STORE_DIR}/ent_conf/vhosts/"${VNAME}"
        fi
    done
    for FILE in "${CONVERTPATH[@]}"; do 
        VFILE=$(echo ${FILE} | awk -F '/' '$6 == "vhosts" {print $7}')
        if [ ! -z "${VFILE}" ]; then
            cp "${FILE}" ${STORE_DIR}/ent_conf/vhosts/"${VFILE}"/
        else    
            cp "${FILE}" ${STORE_DIR}/ent_conf/
        fi    
    done
}

set_ent_cache(){
    grep '<cache>' ${LS_DIR}/conf/httpd_config.xml >/dev/null
    if [ ${?} = 0 ]; then
        echoG 'Detect cache, skip!'
    else
        echoG 'Enable Cache'
        sed -i '/<\/scriptHandlerList>/a\
  <cache> \
    <cacheEngine>7</cacheEngine> \
    <storage> \
      <cacheStorePath>/home/lscache</cacheStorePath> \
    </storage> \
  </cache>
' ${LS_DIR}/conf/httpd_config.xml
    fi
}

set_ent_htaccess(){
    grep '<htAccess>' ${LS_DIR}/conf/httpd_config.xml >/dev/null
    if [ ${?} = 0 ]; then
        echoG 'Detect htaccess, skip!'
    else
        echoG 'Enable htaccess'
        sed -i '/<\/logging>/a\
  <htAccess> \
    <allowOverride>31</allowOverride> \
  </htAccess>
' ${LS_DIR}/conf/httpd_config.xml
    fi
}

restore_ols() {
    if ${LS_DIR}/bin/lshttpd -v | grep -q Open ; then
        echoG 'You already have OpenLiteSpeed installed...'
        exit 0
    fi
    echo -e "Listing all the backup files: \n"
    ls ${STORE_DIR} | grep OLS_  --color=never
    printf "%s" "Please input the backup directory: "
    read ols_backup_dir

    if [[ ! -d ${STORE_DIR}/${ols_backup_dir} ]] ; then
      echoR 'The dir seems not exists.'
      exit 1
    fi
    if [[ ! -f ${STORE_DIR}/${ols_backup_dir}/conf/httpd_config.conf ]] ; then
        echoR 'Main conf file is missing...'
        exit 1
    else
        ${PKG_TOOL} install openlitespeed -y >/dev/null 2>&1
        rm -rf ${LS_DIR}/conf/*
        cp -a ${STORE_DIR}/${ols_backup_dir}/conf/* ${LS_DIR}/conf/
        chown -R lsadm:lsadm ${LS_DIR}/conf
        chown root:root ${LS_DIR}/logs
        chmod 755 ${LS_DIR}/logs
        restart_lsws
        rm -f ${LS_DIR}/autoupdate/*
        echoG 'OpenLiteSpeed Restored...'
        webadmin_reset
    fi
}

download_lsws() {
    echoG 'Download LiteSpeed Web Server.'
    LATEST_VERSION=$(curl -s -S http://update.litespeedtech.com/ws/latest.php | head -n 1 | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
    MAJOR_VERSION=$(echo "${LATEST_VERSION}" | cut -c 1)
    BITNESS=$(uname -m)
    if [ "${BITNESS}" == "i686" ]; then
        BITNESS="i386"
    fi
    rm -f lsws-latest.tar.gz; rm -rf "lsws-${LATEST_VERSION}"
    cd /opt; curl -s -S -o "lsws-latest.tar.gz" https://www.litespeedtech.com/packages/"${MAJOR_VERSION}".0/lsws-"${LATEST_VERSION}"-ent-"${BITNESS}"-linux.tar.gz
    check_return
    tar -xzf "lsws-latest.tar.gz"; cd "lsws-${LATEST_VERSION}"
}

write_license() {
    if [[ ${LICENSE_KEY} == 'TRIAL' ]] ; then
        wget -q http://license.litespeedtech.com/reseller/trial.key
        check_return
        if ./lshttpd -V |& grep  "ERROR" ; then
            ./lshttpd -V
            echoR 'It apeears to have some issue with license , please check above result...'
            exit 1
        fi
        echoG 'License seems valid...'
    else
        echo ${LICENSE_KEY} > serial.no
        if ./lshttpd -r |& grep "ERROR" ; then
            ./lshttpd -r
            echoR 'It apeears to have some issue with license , please check above result...'
            exit 1
        fi
        echoG 'License seems valid...'    
    fi
}

check_license(){
    KEY_SIZE=${#1}
    TMP=$(echo ${1} | cut -c5)
    TMP2=$(echo ${1} | cut -c10)
    TMP3=$(echo ${1} | cut -c15)
    if [[ ${TMP} == "-" ]] && [[ ${TMP2} == "-" ]] && [[ ${TMP3} == "-" ]] && [[ ${KEY_SIZE} == "19" ]] ; then
        echoG 'License key format check...'
    elif [[ ${1} == "trial" ]] || [[ ${1} == "TRIAL" ]] || [[ ${1} == "Trial" ]] ; then
        echoG 'Trial license format check...'
        LICENSE_KEY='TRIAL'
    else
        echoR 'License key seems incorrect, please verify'
        exit 1
    fi
}

license_input() {
    echo -e "\nPlease note that your server has \e[31m$TOTAL_RAM MB\e[39m RAM"   
    if [ "$TOTAL_RAM" -gt 2048 ]; then
        echo "$TOTAL_RAM is greater than 2048 MB RAM"
		echo -e "If you are using \e[31mFree Starter\e[39m LiteSpeed license, It will not start due to 2GB RAM limit."
	fi
    
    echo -e "If you do not have any license, you can also use trial license (if server has not used trial license before), type \e[31mTRIAL\e[39m\n"
    while true; do
        printf "%s" "Please input your serial number for LiteSpeed WebServer Enterprise: "
        read LICENSE_KEY
        if [ -z "${LICENSE_KEY}" ] ; then
            echo -e "\nPlease provide license key\n"
        else
            echo -e "The serial number you input is: \e[31m${LICENSE_KEY}\e[39m"
            printf "%s"  "Please verify it is correct. [y/N]: "
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                break
            fi
        fi
    done
    check_license "${LICENSE_KEY}"
    write_license
}

restart_lsws(){
    ${LS_DIR}/bin/lswsctrl stop > /dev/null 2>&1
    pkill lsphp
    systemctl stop lsws
    systemctl start lsws
    systemctl status lsws
    if [[ ${?} == '0' ]] ; then
        echo -e "\nLiteSpeed has started and running...\n"
    else
        echo -e "Something went wrong , LSWS can not be started."
        exit 1
    fi    
}

check_return() {
  if [[ ${?} -eq "0" ]] ; then
      :
  else
      echoR 'Command failed, exiting...'
      exit 1
  fi
}

gen_store_dir(){
    if [[ ! -d ${STORE_DIR} ]] ; then
        mkdir ${STORE_DIR}
    fi
    if [[ ! -d ${STORE_DIR}/conf ]] ; then
        mkdir ${STORE_DIR}/conf
    else
        rm -rf ${STORE_DIR}/conf/*
    fi
}

uninstall_ols() {
    echoG 'Uninstall OpenLiteSpeed.'
    if [[ -f ${LS_DIR}/conf/httpd_config.conf ]] ; then
        DATE=`date +%Y-%m-%d_%H%M`
        mkdir ${STORE_DIR}/OLS_backup_$DATE/
        echoG "Backing up current OpenLiteSpeed configuration file to ${STORE_DIR}/OLS_backup_${DATE}/"
        cp -a ${LS_DIR}/conf/ ${STORE_DIR}/OLS_backup_${DATE}/
        ${LS_DIR}/bin/lswsctrl stop > /dev/null 2>&1
        pkill lsphp
        systemctl stop lsws
        ${PKG_TOOL} remove openlitespeed -y > /dev/null 2>&1
        check_return
        echoG 'OpenLiteSpeed successfully removed...'
    fi
}

rm_lsws_autoupdate(){
    rm -f ${LS_DIR}/autoupdate/*
}

install_lsws() {
    echoG 'Installing LiteSpeed Enterprise...'
    sed -i '/^license$/d' install.sh
    sed -i 's/read TMPS/TMPS=0/g' install.sh
    sed -i 's/read TMP_YN/TMP_YN=N/g' install.sh
    sed -i 's/read TMP_URC/TMP_URC=N/g' install.sh
    sed -i '/read [A-Z]/d' functions.sh
    sed -i 's/HTTP_PORT=$TMP_PORT/HTTP_PORT=443/g' functions.sh
    sed -i 's/ADMIN_PORT=$TMP_PORT/ADMIN_PORT=7080/g' functions.sh
    sed -i "/^license()/i\
    PASS_ONE=${ADMIN_PASS}\
    PASS_TWO=${ADMIN_PASS}\
    TMP_USER=${USER}\
    TMP_GROUP=${GROUP}\
    TMP_PORT=''\
    TMP_DEST=''\
    ADMIN_USER=''\
    ADMIN_EMAIL=''
    " functions.sh
    COUNTER=0
    ./install.sh >/dev/null 2>&1
    if [[ ${?} != "0" ]] ; then
        while [ ${COUNTER} -le 4 ]; do
            ./install.sh
            if [[ ${?} == "0" ]] ; then
                break
            elif [[ ${COUNTER} == "3" ]]; then
                echoR 'Unable to install LiteSpeed Enterprise, switching back to OpenLiteSpeed...'
                restore_ols
                exit 1
            fi
            COUNTER=$((var+1))
        done
    fi
    echoG 'LiteSpeed Enterprise installed...'
    set_ent_cache
    set_ent_htaccess
    rm_lsws_autoupdate
    restart_lsws
}

check_root_user(){
    if [[ $(id -u) != 0 ]]  > /dev/null; then
        echoR 'You must have root privileges to run this script. ...'
        exit 1
    fi
}

check_no_lsws(){
    if ${LS_DIR}/bin/lshttpd -v | grep -q Enterprise ; then
        echoG 'You have already installed LiteSpeed Enterprise...'
        exit 1
    fi    
}

main_pre_check(){
    check_root_user
    check_no_panel
    check_no_lsws
    check_pkg_manage
    check_php
}

main_pre_gen(){
    gen_store_dir
    add_converter_script
}

main_restore_ols(){
    check_root_user
    check_pkg_manage
    gen_store_dir
    restore_ols
}

main_to_lsws(){
    main_pre_check
    main_pre_gen
    gen_ent_config
    download_lsws
    license_input
    uninstall_ols
    install_lsws
    webadmin_reset
}

case ${1} in
    -[hH] | -help | --help)
        show_help
        ;;
    -[rR] | -restore | --restore)
        main_restore_ols; exit 0
        ;;
    -[lL] | -lsws | --lsws)
        main_to_lsws; exit 0
        ;;
    *) 
        main_to_lsws; exit 0
        ;;
esac
