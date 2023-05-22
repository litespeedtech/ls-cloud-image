#!/bin/bash
USER='www-data'
GROUP='www-data'
HMPATH='/root'
DBPASSPATH="${HMPATH}/.db_password"
APT='apt-get -qq'
YUM='yum -q'
DATA_STO_DIR='/var/nfs/wp'
LAN_IP_FILTER='10.'
FILTER_NETMASK='20'
ALLERRORS=0

function echoY
{
    FLAG=$1
    shift
    echo -e "\033[38;5;148m$FLAG\033[39m$@"
}

function echoG
{
    FLAG=$1
    shift
    echo -e "\033[38;5;71m$FLAG\033[39m$@"
}

function echoB
{
    FLAG=$1
    shift
    echo -e "\033[38;1;34m$FLAG\033[39m$@"
}

function echoR
{
    FLAG=$1
    shift
    echo -e "\033[38;5;203m$FLAG\033[39m$@"
}

function echoW
{
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}

function echoNW
{
    FLAG=${1}
    shift
    echo -e "\033[1m${FLAG}\033[0m${@}"
}

function echoCYAN
{
    FLAG=$1
    shift
    echo -e "\033[1;36m$FLAG\033[0m$@"
}

function silent
{
    if [ "${VERBOSE}" = '1' ] ; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

function check_root
{
    local INST_USER=`id -u`
    if [ $INST_USER != 0 ] ; then
        echoR "Sorry, only the root user can install."
        echo
        exit 1
    fi
}

function check_rsync
{
    which rsync  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install rsync
        else
            ${APT} -y install rsync
        fi

        which rsync  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occured during rsync installation."
            ALLERRORS=1
        fi
    fi
}

function check_provider
{
    if [ "$(dmidecode -s bios-vendor)" = 'Vultr' ];then
        echoG 'Platform Provider is Vultr'
    else
        echoR 'Platform Provider is not Vultr, do you still want to continue? [y/N] ' 
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
            echoG 'Continue the setup'
        else
            exit 0    
        fi        
    fi
}

function check_lan_ipv4
{
    ### Filter IP start from 10.*
    FILTER_RESULT=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -e "^${LAN_IP_FILTER}")
    FILTER_MATCH_NUM="$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -e "^${LAN_IP_FILTER}" | wc -l)"
    if [ "${FILTER_MATCH_NUM}" = '0' ]; then
        echoR "No IP mathc with ^${LAN_IP_FILTER} filter, please check manually! exit! "
        ip addr; exit 1
    elif [ "${FILTER_MATCH_NUM}" = '1' ]; then
        echoG "Found IP for NFS service: ${FILTER_RESULT}" 
    else
        echoY "Found multiple IP match with ^${LAN_IP_FILTER} filter, please check it manually! exit!"
        ip addr; exit 1
    fi
    FILTER_NETMASK=$(ip -4 addr | grep "${FILTER_RESULT}" | awk -F '/' '{ print $2 }' | cut -f 1 -d " ")
}

function usage
{
    echo -e "\033[1mOPTIONS\033[0m"
    echoW " --dbname [DATABASENAME]           " "To set the database name in the database instead of using a random one."
    echoW " --dbuser [DBUSERNAME]             " "To set the APP username in the database instead of using a random one."
    echoW " --dbpassword [PASSWORD]           " "To set the APP user password in database instead of using a random one."    
    echoNW "  -H,    --help                   " "${EPACE} To display help messages."
    echo
    exit 0    
}

function change_owner
{
    chown -R ${USER}:${GROUP} ${1}
}

function prepare_data_dir
{
    mkdir -p "${DATA_STO_DIR}"
    change_owner "${DATA_STO_DIR}"
}

function centos_install_nfs
{
    silent ${YUM} -y install nfs-utils nfs-utils-lib 
}


function debian_install_nfs
{
    silent ${APT} -y install nfs-kernel-server
}

function install_nfs
{
    echoG 'Install nfs'
    if [ "$OSNAME" = "centos" ] ; then
        centos_install_nfs
    else
        debian_install_nfs
    fi
}

function set_nfs
{
    echoG 'Config nfs'
    FIRST_THREE_SEC=${FILTER_RESULT%.*}
    echo "${DATA_STO_DIR}    ${FIRST_THREE_SEC}.0/${FILTER_NETMASK}(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports

    if [ "$OSNAME" = "centos" ] ; then
        silent  systemctl restart nfs
    else
        silent systemctl restart nfs-kernel-server   
    fi
}


function disable_needrestart
{
    if [ -d /etc/needrestart/conf.d ]; then
        echoG 'List Restart services only'
        cat >> /etc/needrestart/conf.d/disable.conf <<END
# Restart services (l)ist only, (i)nteractive or (a)utomatically. 
\$nrconf{restart} = 'l'; 
# Disable hints on pending kernel upgrades. 
\$nrconf{kernelhints} = 0;         
END
    fi
}

function update_system(){
    echoG 'System update'
    if [ "$OSNAME" = "centos" ] ; then
        silent ${YUM} update -y >/dev/null 2>&1
    else
        disable_needrestart
        silent ${APT} update && ${APT} upgrade -y >/dev/null 2>&1
    fi
}

function check_os
{
    if [ -f /etc/centos-release ] ; then
        OSNAME=centos
    elif [ -f /etc/redhat-release ] ; then
        OSNAME=centos        
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian        
    else
        echoR 'Platform is not support, exit!'; exit 1
    fi
}

function db_password_file    
{
    echoG 'Create db fiile'
    if [ -f ${DBPASSPATH} ]; then 
        echoY "${DBPASSPATH} already exist!, will recreate a new file"
        rm -f ${DBPASSPATH}
    fi    
    touch "${DBPASSPATH}" 
}

function save_db_root_pwd
{
    echo "mysql root password is [$ROOTPASSWORD]." >> ${DBPASSPATH}
}

function save_db_user_pwd
{
    echo "mysql WordPress DataBase name is [$DATABASENAME], username is [$USERNAME], password is [$USERPASSWORD]." >> ${DBPASSPATH}
}

function random_password
{
    if [ ! -z ${1} ]; then 
        TEMPPASSWORD="${1}"
    else    
        TEMPPASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi
}

function random_strong_password
{
    if [ ! -z ${1} ]; then 
        TEMPPASSWORD="${1}"
    else    
        TEMPPASSWORD=$(openssl rand -base64 32)
    fi
}

function main_gen_password
{
    random_strong_password "${ROOTPASSWORD}"
    ROOTPASSWORD="${TEMPPASSWORD}"
    random_password "${USERNAME}"
    USERNAME="${TEMPPASSWORD}"
    random_password "${DATABASENAME}"
    DATABASENAME="${TEMPPASSWORD}"     
    random_strong_password "${USERPASSWORD}"
    USERPASSWORD="${TEMPPASSWORD}" 
}

function centos_install_mariadb
{
    echoB "${FPACE} - Install MariaDB"
    silent ${YUM} -y install MariaDB-server MariaDB-client
    silent systemctl enable mariadb
    silent systemctl start  mariadb
}    

function debian_install_mariadb
{
    echoB "${FPACE} - Install MariaDB"
    silent ${APT} -y install mariadb-server
    silent service mysql start
    if [ ${?} != 0 ]; then
        service mariadb start
    fi
}    

function check_cur_status
{
    which mariadb  >/dev/null 2>&1
    if [ $? = 0 ] ; then
        echoY 'MariaDB is already installed, exit!'; exit 1
    fi
}    

function install_mariadb
{
    echoG "Start Install MariaDB"
    if [ "$OSNAME" = 'centos' ] ; then
        centos_install_mariadb
    else
        debian_install_mariadb
    fi
    if [ $? != 0 ] ; then
        echoR "An error occured when starting the MariaDB service. "
        echoR "Please fix this error and try again. Aborting installation!"
        exit 1
    fi
    echoG "End Install MariaDB"    
}    

function set_db_root
{
    echoB "${FPACE} - Set MariaDB root"
    mysql -uroot -e "flush privileges;"
    mysqladmin -uroot -p$ROOTPASSWORD password $ROOTPASSWORD
    if [ $? != 0 ] ; then
        echoR "Failed to set MySQL root password to $ROOTPASSWORD, it may already have a root password."
    fi    
}

function set_db_user
{
    echoB "${FPACE} - Set MariaDB user"
    mysql -uroot -p$ROOTPASSWORD  -e "DELETE FROM mysql.user WHERE User = '$USERNAME@localhost';"
    echo `mysql -uroot -p$ROOTPASSWORD -e "SELECT user FROM mysql.user"` | grep "$USERNAME" >/dev/null
    if [ $? = 0 ] ; then
        echoG "user $USERNAME exists in mysql.user"
    else
        mysql -uroot -p$ROOTPASSWORD  -e "CREATE USER $USERNAME@localhost IDENTIFIED BY '$USERPASSWORD';"
        if [ $? = 0 ] ; then
            mysql -uroot -p$ROOTPASSWORD  -e "GRANT ALL PRIVILEGES ON *.* TO '$USERNAME'@localhost IDENTIFIED BY '$USERPASSWORD';"
        else
            echoR "Failed to create MySQL user $USERNAME. This user may already exist. If it does not, another problem occured."
            echoR "Please check this and update the wp-config.php file."
            ERROR="Create user error"
        fi
    fi    
    mysql -uroot -p$ROOTPASSWORD  -e "CREATE DATABASE IF NOT EXISTS $DATABASENAME;"
    if [ $? = 0 ] ; then
        mysql -uroot -p$ROOTPASSWORD  -e "GRANT ALL PRIVILEGES ON $DATABASENAME.* TO '$USERNAME'@localhost IDENTIFIED BY '$USERPASSWORD';"
    else
        echoR "Failed to create database $DATABASENAME. It may already exist. If it does not, another problem occured."
        echoR "Please check this and update the wp-config.php file."
        if [ "x$ERROR" = "x" ] ; then
            ERROR="Create database error"
        else
            ERROR="$ERROR and create database error"
        fi
    fi
    mysql -uroot -p$ROOTPASSWORD  -e "flush privileges;"

    if [ "x$ERROR" = "x" ] ; then
        echoG "Finished MySQL setup without error."
    else
        echoR "Finished MySQL setup - some error(s) occured."
    fi    
}

function check_value_follow
{
    FOLLOWPARAM=$1
    local PARAM=$1
    local KEYWORD=$2

    if [ "$1" = "-n" ] || [ "$1" = "-e" ] || [ "$1" = "-E" ] ; then
        FOLLOWPARAM=
    else
        local PARAMCHAR=$(echo $1 | awk '{print substr($0,1,1)}')
        if [ "$PARAMCHAR" = "-" ] ; then
            FOLLOWPARAM=
        fi
    fi

    if [ -z "$FOLLOWPARAM" ] ; then
        if [ ! -z "$KEYWORD" ] ; then
            echoR "Error: '$PARAM' is not a valid '$KEYWORD', please check and try again."
            usage
        fi
    fi
}

function befor_install_display
{
    echo
    echoCYAN "Starting to setup Data Storae Node on Vultr server with the parameters below,"
    echoY "MariaDB root Password:    " "$ROOTPASSWORD"
    echoY "Database name:            " "$DATABASENAME"
    echoY "Database username:        " "$USERNAME"
    echoY "Database password:        " "$USERPASSWORD"     
    echo
    echoNW "Your password will be written to file: ${DBPASSPATH}"  
    printf 'Are these settings correct? Type n to quit, otherwise will continue. [Y/n]  '
        read answer
        if [ "$answer" = "N" ] || [ "$answer" = "n" ] ; then
            echoG "Aborting installation!"
            exit 0
        fi    
    echoCYAN 'Start OpenLiteSpeed one click installation >> >> >> >> >> >> >>'    
}    

function after_install_display
{
    if [ "$ALLERRORS" = "0" ] ; then
        echoG "Congratulations! Installation finished."
    else
        echoY "Installation finished. Some errors seem to have occured, please check this as you may need to manually fix them."
    fi
        echoCYAN 'End OpenLiteSpeed one click installation << << << << << << <<'
    echo
}    

function main_mariadb
{
    install_mariadb
    set_db_root
    save_db_root_pwd
    set_db_user
    save_db_user_pwd
}

function main_nfs
{
    install_nfs
    prepare_data_dir
    set_nfs
}

function main_init_check
{
    check_root
    check_os
    check_provider
    check_lan_ipv4
    check_cur_status
}

function main_init_package
{
    update_system
    check_rsync
    check_curl
}

function main
{
    main_init_check
    main_gen_password
    befor_install_display
    main_mariadb
    main_nfs
    after_install_display
}    


while [ ! -z "${1}" ] ; do
    case "${1}" in
        --dbname )         
                check_value_follow "$2" "database name"
                shift
                DATABASENAME=$FOLLOWPARAM
                ;;
        --dbuser )         
                check_value_follow "$2" "database username"
                shift
                USERNAME=$FOLLOWPARAM
                ;;
        --dbpassword )     
                check_value_follow "$2" ""
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                USERPASSWORD=$FOLLOWPARAM
                ;;    
        -[hH] | --help )           
                usage
                ;;                
        * )                     
                usage
                ;;
    esac
    shift
done

main