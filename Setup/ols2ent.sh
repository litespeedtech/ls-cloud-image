#!/bin/bash

# 1. read domain name , docroot and SSL setting
# 2. install litespeed enterprise
# 3. create vhost with Apache conf
# 4. webadmin console pass will be reset when convert.

TOTAL_RAM=$(free -m | awk '/Mem\:/ { print $2 }')
LICENSE_KEY=""
ADMIN_PASS="1234567"
LS_DIR='/usr/local/lsws'
STORE_DIR='/opt'
CONF_URL='https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Setup/conf/ols2ent'

check_pkg_manage(){
    if hash apt > /dev/null 2>&1 ; then
      pkg_tool='apt'
    elif hash yum > /dev/null 2>&1 ; then
      pkg_tool='yum'
    else
      echo -e "can not detect package management tool ..."
      exit 1
    fi
}
check_pkg_manage

restore_ols() {
    echo -e "Restore OpenLiteSpeed in case LiteSpeed Enterprise installation failed..."
    echo -e "Listing all the backup files\n"
    ls /root/.litespeed_conf/ | grep OLS_  --color=never
    echo -e "\nPlease input the backup directory :\n"
    printf "%s" "e.g. OLS_backup_2020-01-01_1111: "
    read ols_backup_dir

    if [[ ! -d /root/.litespeed_conf/$ols_backup_dir ]] ; then
      echo -e "the dir seems not exists."
      exit 1
    else
      if [[ ! -f /root/.litespeed_conf/$ols_backup_dir/conf/httpd_config.conf ]] ; then
          echo -e "main conf file is missing..."
          exit 1
      else
          $pkg_tool install openlitespeed -y
          rm -rf /usr/local/lsws/conf/*
          cp -a /root/.litespeed_conf/$ols_backup_dir/conf/* /usr/local/lsws/conf/
          chown -R lsadm:lsadm /usr/local/lsws/conf
          chown root:root /usr/local/lsws/logs
          chmod 755 /usr/local/lsws/logs
          systemctl stop lsws
          /usr/local/lsws/bin/lswsctrl stop > /dev/null 2>&1
          pkill lsphp
          systemctl start lsws
          check_return
          systemctl status lsws
          rm -f /usr/local/lsws/autoupdate/*
          echo -e "OpenLiteSpeed Restored..."
      fi
    fi
}

licesne_input() {
    echo -e "\nPlease note that your server has \e[31m$TOTAL_RAM MB\e[39m RAM"
    echo -e "If you are using \e[31mFree Start\e[39m license, It will not start due to \e[31m2GB RAM limit\e[39m.\n"
    echo -e "If you do not have any license, you can also use trial license (if server has not used trial license before), type \e[31mTRIAL\e[39m\n"

    printf "%s" "Please input your serial number for LiteSpeed WebServer Enterprise: "
    read LICENSE_KEY
    if [ -z "$LICENSE_KEY" ] ; then
        echo -e "\nPlease provide license key\n"
        exit 1
    fi

    echo -e "The serial number you input is: \e[31m$LICENSE_KEY\e[39m"
    printf "%s"  "Please verify it is correct. [y/N]: "
    read TMP_YN
    if [ -z "$TMP_YN" ] ; then
        echo -e "\nPlease type \e[31my\e[39m\n"
        exit 1
    fi

    KEY_SIZE=${#LICENSE_KEY}
    TMP=$(echo $LICENSE_KEY | cut -c5)
    TMP2=$(echo $LICENSE_KEY | cut -c10)
    TMP3=$(echo $LICENSE_KEY | cut -c15)

    if [[ $TMP == "-" ]] && [[ $TMP2 == "-" ]] && [[ $TMP3 == "-" ]] && [[ $KEY_SIZE == "19" ]] ; then
        echo -e "\nLicense key set..."
        echo -e "\nChecking License validation...\n"
    elif [[ $LICENSE_KEY == "trial" ]] || [[ $LICENSE_KEY == "TRIAL" ]] || [[ $LICENSE_KEY == "Trial" ]] ; then
        echo -e "\nTrial license set..."
        echo -e "\nChecking License validation...\n"
        LICENSE_KEY="TRIAL"
    else
        echo -e "\nLicense key seems incorrect, please verify\n"
        echo -e "\nIf you are copying/pasting, please make sure you didn't paste blank space...\n"
        exit 1
    fi
}

check_license() {
    latest_version=$(curl -s -S http://update.litespeedtech.com/ws/latest.php | head -n 1 | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
    major_version=$(echo "${latest_version}" | cut -c 1) 
    bitness=$(uname -m)
    if [ "${bitness}" == "i686" ]; then
        bitness="i386"
    fi
    rm -f lsws-latest.tar.gz
    rm -rf "lsws-${latest_version}"
    curl -s -S -o "lsws-latest.tar.gz" https://www.litespeedtech.com/packages/"${major_version}".0/lsws-"${latest_version}"-ent-"${bitness}"-linux.tar.gz
    check_return
    tar -xzf "lsws-latest.tar.gz"
    cd "lsws-${latest_version}"

    if [[ $LICENSE_KEY == "TRIAL" ]] ; then
        wget -q http://license.litespeedtech.com/reseller/trial.key
        check_return
    else
        echo $LICENSE_KEY > serial.no
    fi

    if [[ $LICENSE_KEY == "TRIAL" ]] ; then
        if ./lshttpd -V |& grep  "ERROR" ; then
            ./lshttpd -V
            echo -e "\n\nIt apeears to have some issue with license , please check above result..."
            exit 1
        fi
    else
        if ./lshttpd -r |& grep "ERROR" ; then
            ./lshttpd -r
            echo -e "\n\nIt apeears to have some issue with license , please check above result..."
            exit 1
        fi
    fi
    echo -e "License seems valid..."
}

check_return() {
  if [[ $? -eq "0" ]] ; then
      :
  else
      echo -e "\ncommand failed, exiting..."
      exit 1
  fi
}

ols_conf_file="/usr/local/lsws/conf/httpd_config.conf"

if [[ ! -d /root/.litespeed_conf ]] ; then
    mkdir /root/.litespeed_conf
fi
#create a dir to save files

if [[ ! -d /root/.litespeed_conf/conf ]] ; then
    mkdir /root/.litespeed_conf/conf
fi
rm -rf /root/.litespeed_conf/conf/*

if [[ ! -d /root/.litespeed_conf/conf/vhosts ]] ; then
    mkdir /root/.litespeed_conf/conf/vhosts
fi
rm -rf /root/.litespeed_conf/conf/vhosts/*


uninstall_ols() {
    DATE=`date +%Y-%m-%d_%H%M`
    mkdir /root/.litespeed_conf/OLS_backup_$DATE/
    echo -e "Backing up current OpenLiteSpeed configuration file to /root/.litespeed_conf/OLS_backup_$DATE/"
    cp -a /usr/local/lsws/conf/ /root/.litespeed_conf/OLS_backup_$DATE/

    echo -e "Uninstalling OpenLiteSpeed..."

    /usr/local/lsws/bin/lswsctrl stop > /dev/null 2>&1
    pkill lsphp
    systemctl stop lsws

    $pkg_tool remove openlitespeed -y
    check_return
    echo -e "OpenLiteSpeed successfully removed..."
}

install_lsws() {

    if [[ $pkg_tool == "apt" ]] ; then
        USER="www-data"
        GROUP="www-data"
    else
        USER="nobody"
        GROUP="nobody"
    fi

    sed -i '/^license$/d' install.sh
    sed -i 's/read TMPS/TMPS=0/g' install.sh
    sed -i 's/read TMP_YN/TMP_YN=N/g' install.sh
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
    chmod +x install.sh
    echo -e "Installing LiteSpeed Enterprise..."
    counter=0
    ./install.sh
    if [[ $? != "0" ]] ; then
      while [ $counter -le 4 ]
      do
        ./install.sh
          if [[ $? == "0" ]] ; then
            break
          elif [[ $counter == "3" ]]; then
            echo -e "\nUnable to install LiteSpeed Enterprise..."
            echo -e "\nSwitching back to OpenLiteSpeed..."
            restore_ols
            exit
          fi
      counter=$((var+1))
      done
      #loop 3 three times see if install success , if not , at 3rd time , revert to OLS
    fi

    echo -e "LiteSpeed Enterprise installed..."
    echo -e "Generating configuration..."
}

lsws_conf_file() {
    if [[ -f /usr/local/lsws/conf/httpd.conf ]] ; then
        rm -f /usr/local/lsws/conf/httpd.conf
    fi

    cp /root/.litespeed_conf/httpd.conf /usr/local/lsws/conf/httpd.conf

    if [[ $pkg_tool == "apt" ]] ; then
        sed -i $'s/Group nobody/Group www-data/' /usr/local/lsws/conf/httpd.conf
        sed -i $'s/User nobody/User www-data/' /usr/local/lsws/conf/httpd.conf
    fi
    wget -O /usr/local/lsws/conf/httpd_config.xml https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Setup/conf/ols2ent/httpd_config.xml
    check_return
    if [[ $pkg_tool == "apt" ]] ; then
        sed -i $'s/<user>nobody<\/user>/<user>www-data<\/user>/' /usr/local/lsws/conf/httpd_config.xml
        sed -i $'s/<group>nobody<\/group>/<group>www-data<\/group>/' /usr/local/lsws/conf/httpd_config.xml
    fi

    rm -rf /usr/local/lsws/conf/vhosts/*
    rm -rf /usr/local/lsws/cachedata/*
    cp -a /root/.litespeed_conf/conf/vhosts/ /usr/local/lsws/conf/
    chown -R lsadm:lsadm /usr/local/lsws/conf
}

write_apache_conf() {

    if [[ ! -f /root/.litespeed_conf/httpd.conf ]] ; then
        wget -q -O /root/.litespeed_conf/httpd.conf https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Setup/conf/ols2ent/httpd.conf
        check_return
    fi

    #main httpd.conf only needs to download once.

    if [[ -d /root/.litespeed_conf/conf/vhosts/${domains[i]} ]] ; then
        rm -rf /root/.litespeed_conf/conf/vhosts/${domains[i]}
    fi

    mkdir /root/.litespeed_conf/conf/vhosts/${domains[i]}

    wget -q -O /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf https://raw.githubusercontent.com/litespeedtech/ls-cloud-image/master/Setup/conf/ols2ent/example.conf
    check_return

    if [[ ${domains[i]} == "wordpress" ]] ; then
        sed -i 's|replacement_domain|'$vhDomain'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    else
        sed -i 's|replacement_domain|'${domains[i]}'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi

    if [[ $vhAliases == "www." ]] ; then
        vhAliases="www.${domains[i]}"
        sed -i 's|replacement_alias|'$vhAliases'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi

    if [[ $vhAliases == "*" ]] ; then
        sed -i 's|replacement_alias|'$vhAliases'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    elif echo $vhAliases | grep -q -P '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$)' ; then
        sed -i 's|replacement_alias|'$vhAliases'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi

    sed -i 's|replacement_adminemail|'$adminEmail'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf

    sed -i 's|replacement_user|'$php_user'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf

    sed -i 's|replacement_group|'$php_group'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf

    if [[ ${domains[i]} == "wordpress" ]] ; then
        sed -i 's|replacement_adminemail|'$adminEmail'|g' /root/.litespeed_conf/httpd.conf
        sed -i 's|replacement_user|'$php_user'|g' /root/.litespeed_conf/httpd.conf
        sed -i 's|replacement_group|'$php_group'|g' /root/.litespeed_conf/httpd.conf
        if [[ $server_ipv6 == "" ]] ; then
            sed -i 's|replacement_IP|'$server_ipv4'|g' /root/.litespeed_conf/httpd.conf
            sed -i 's|replacement_servername|'$server_ipv4'|g' /root/.litespeed_conf/httpd.conf
        else
            sed -i 's|replacement_IP:80|'$server_ipv4':80 '$server_ipv6':80|g' /root/.litespeed_conf/httpd.conf
            sed -i 's|replacement_IP:443|'$server_ipv4':443 '$server_ipv6':443|g' /root/.litespeed_conf/httpd.conf
            sed -i 's|replacement_servername|'$server_ipv4'\n\ \ \ \ ServerAlias '$server_ipv4' '$server_ipv6' |g' /root/.litespeed_conf/httpd.conf
        fi

        if [[ -f $certFile ]] ; then
            sed -i 's|replacement_cert_file|'$certFile'|g' /root/.litespeed_conf/httpd.conf
        else
            sed -i 's|replacement_cert_file|/usr/local/lsws/admin/conf/webadmin.crt|g' /root/.litespeed_conf/httpd.conf
        fi

        if [[ -f $keyFile ]] ; then
            sed -i 's|replacement_key_file|'$keyFile'|g' /root/.litespeed_conf/httpd.conf
        else
            sed -i 's|replacement_key_file|/usr/local/lsws/admin/conf/webadmin.key|g' /root/.litespeed_conf/httpd.conf
        fi
    fi

    if [[ $docRoot ==  "\$VH_ROOT" ]] ; then
        docRoot=$VH_ROOT
    fi
    sed -i 's|replacement_docroot|'$docRoot'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    sed -i 's|replacement_log|'/usr/local/lsws/logs/${domains[i]}-access.log'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    php_ver=$(echo $php_binary | tr -dc '0-9')
    sed -i 's|replacement_php_ver|'php$php_ver'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf

    if [[ $server_ipv6 == "" ]] ; then
        sed -i 's|replacement_IP|'$server_ipv4'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    else
        sed -i 's|replacement_IP:80|'$server_ipv4':80 '$server_ipv6':80|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
        sed -i 's|replacement_IP:443|'$server_ipv4':443 '$server_ipv6':443|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi

    if [[ -f $certFile ]] ; then
        sed -i 's|replacement_cert_file|'$certFile'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    else
        sed -i 's|replacement_cert_file|/usr/local/lsws/admin/conf/webadmin.crt|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi

    if [[ -f $keyFile ]] ; then
        sed -i 's|replacement_key_file|'$keyFile'|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    else
        sed -i 's|replacement_key_file|/usr/local/lsws/admin/conf/webadmin.key|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi
    #replace cert/key to webadmin's if there is none.

    if [[ $phpmyadmin == "ON" ]] ; then
        sed -i 's|php_my_admin_directive|Alias /phpmyadmin/ /var/www/phpmyadmin/|g' /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    else
        sed -i "/\b\php_my_admin_directive\b/d" /root/.litespeed_conf/conf/vhosts/${domains[i]}/${domains[i]}.conf
    fi
}



get_conf_from_vhconf() {
    #this should get php version, php user, docroot, domains/alias, admin mail and SSL setting.

    echo "main domain detected: ${domains[i]}"
    echo "vhost root detected: $VH_ROOT"

    grep -q "phpmyadmin" $VH_CONF
    if [[ $? == 0 ]] ; then
        phpmyadmin="ON"
    else
        phpmyadmin="OFF"
    fi
    #special check for phpmyadmin context

    php_binary=$(grep "path" $VH_CONF | awk 'NR==1{print $2}')
    if [[ $php_binary == "" ]] ; then
        php_binary=$(grep "path" $ols_conf_file | awk 'NR==1{print $2}')
    fi
    echo "PHP binary detected: $php_binary"

    php_user=$(grep "extUser" $VH_CONF | awk 'NR==1{print $2}')
    if [[ $php_user == "" ]] ; then
        php_user="www-data"
    fi
    echo "PHP user detected: $php_user"

    php_group=$(grep "extGroup" $VH_CONF | awk 'NR==1{print $2}')
    if [[ $php_group == "" ]] ; then
        php_group="www-data"
    fi
    echo "PHP group detected: $php_group"

    adminEmail=$(grep "adminEmails" $VH_CONF | awk 'NR==1{print $2}')
    if [[ $adminEmail == "" ]] ; then
        adminEmail=$(grep "adminEmails" $ols_conf_file | awk 'NR==1{print $2}')
    fi
    echo "Admin Email detected: $adminEmail"

    docRoot=$(grep "docRoot" $VH_CONF | awk 'NR==1{print $2}')
    echo "Document root detected: $docRoot"

    vhDomain=$(grep "vhDomain" $VH_CONF | awk 'NR==1{print $2}')
    if [[ $vhDomain == "" ]] ; then
        #vhDomain=$(cat $ols_conf_file | grep ${domains[i]} | grep map | awk 'NR==1{print $3}')
        echo ${domains[i]} | grep -P '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$)'
        if [[ $? != 0 ]] ; then
            #if not 0 , invalid domain , probably wordpress as domain
            #then get the domain from OLS conf
            vhDomain=$(cat $ols_conf_file | grep wordpress | grep map | awk '{ print substr($0, index($0,$4)) }' | head -n 1)
            vhDomain=${vhDomain%,*}
        fi
    fi
    echo "Vhost domain detected: $vhDomain"
    vhAliases=$(grep "vhAliases" $VH_CONF | awk 'NR==1{print $2}')
    if [[ $vhAliases == "" ]] ; then
        if [[ $vhDomain == "*" ]] ; then
            vhAliases="*"
        else
            vhAliases=$(cat $ols_conf_file | grep wordpress | grep map | awk '{ print substr($0, index($0,$4)) }' | head -n 1)
            vhAliases=$(echo $vhAliases | sed "s/${vhDomain}, //g")
        fi
    fi
    echo "Vhost alias detected: $vhAliases"

    keyFile=$(grep "keyFile" $VH_CONF | awk 'NR==1{print $2}')
    echo "Key file detected: $keyFile"

    certFile=$(grep "certFile" $VH_CONF | awk 'NR==1{print $2}')
    echo "Cert file detected: $certFile"
    #if returns empty ,  try get from main conf

}

get_conf_from_main() {
    flag="0"
    while [[ $flag == "0" ]]
        do
            start_line=$(( $start_line + 1 ))
            output=$(sed "${start_line}q;d" $ols_conf_file)
            if [[ $output != *"$end_mark"* ]] ; then
                if [[ $output == *"vhRoot"* ]] ; then
                    output=${output//" "/}
                    output=${output//"vhRoot"/}
                    VH_ROOT=$output
                fi
                if [[ $output == *"configFile"* ]] ; then
                    output=${output//" "/}
                    output=${output//"configFile"/}
                    VH_CONF=$output
                fi
            else
                flag="1"
            fi
        done
}

if [[ $(id -u) != 0 ]]  > /dev/null; then
    echo -e "\nYou must have root privileges to run this script. ...\n"
    exit 1
else
	  echo -e "\nYou are runing as root...\n"
fi


if [[ $1 == "--restore" ]] || [[ $1 == "-r" ]] || [[ $1 == "restore" ]] ; then
    if /usr/local/lsws/bin/lshttpd -v | grep -q Open ; then
        echo -e "You arelady have OpenLiteSpeed installed..."
        exit 1
    else
        echo -e "Prepare to restore OpenLiteSpeed..."
    fi
    restore_ols
    exit
fi

if /usr/local/lsws/bin/lshttpd -v | grep -q Enterprise ; then
    echo -e "You have already installed LiteSpeed Enterprise..."
    exit 1
fi

server_ipv4=$(curl -S -s -4 https://cyberpanel.sh/?ipv4)
server_ipv6=$(curl -S -s -6 https://cyberpanel.sh/?ipv6)

if [[ $? != "0" ]] ; then
    #no ipv6 , skip it
    server_ipv6=""
else
    server_ipv6="[$server_ipv6]"
    #enclose it with [ ] as Apache requires it
fi

licesne_input
check_license
#ask and check license before everything , if user doesn't have valid license , following functions no need to be executed anymore.


declare -a vhosts
declare -a domains
for i in $(grep "virtualhost" $ols_conf_file);
    do
        vhosts=("${vhosts[@]}" "$i")
    done
#above code to get all virtualhost list in main conf.

vhosts=( "${vhosts[@]/\{/}" )
vhosts=( "${vhosts[@]/virtualhost/}" )

for i in ${!vhosts[@]} ;
    do
        if [[ ${vhosts[i]} != "" ]] ; then
            domains=( "${domains[@]}" "${vhosts[i]}" )
        fi
    done

start_mark="{"
end_mark="}"
i="0"
while [[ $i -ne ${#domains[@]} ]]
    do
        echo "detected ${domains[i]}..."
        if [[ ${domains[i]} != "Example" ]] ; then
            #disgard the example vhost.
            start_line=$(grep -n "virtualhost ${domains[i]}" $ols_conf_file | awk -F: '{ print $1 }' )
            get_conf_from_main
            #this get vh_root and vh_conf location.

            echo "vhost root is $VH_ROOT"
            echo "vhost conf is $VH_CONF"

            get_conf_from_vhconf
            #this should get php version, php user, docroot, domains/alias and SSL setting.

            write_apache_conf
        fi
        i=$(( $i + 1 ))
    done


if [[ -f /usr/local/lsws/conf/httpd_config.conf ]] ; then
    #check if OLS conf exists or not , if so , back up and uninstall it
    uninstall_ols
fi
if [[ ! -f /usr/local/lsws/conf/httpd_config.xml ]] ; then
    #check if LSWS conf exists or not , if not , install LSWS
    install_lsws
    rm -f /usr/local/lsws/autoupdate/*
fi

lsws_conf_file

if [[ -f /usr/local/lsws/admin/fcgi-bin/admin_php ]] ; then
	  php_command="admin_php"
else
	  php_command="admin_php5"
fi

WEBADMIN_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
TEMP=`/usr/local/lsws/admin/fcgi-bin/${php_command} /usr/local/lsws/admin/misc/htpasswd.php ${WEBADMIN_PASS}`
echo "" > /usr/local/lsws/admin/conf/htpasswd
echo "admin:$TEMP" > /usr/local/lsws/admin/conf/htpasswd

/usr/local/lsws/bin/lswsctrl stop > /dev/null 2>&1
pkill lsphp
systemctl stop lsws
systemctl start lsws
systemctl status lsws
if [[ $? == "0" ]] ; then
    echo -e "\nLiteSpeed Enterprise has started and running...\n"
    echo -e "\nNew WebAdmin Console access: admin , $WEBADMIN_PASS\n"
    echo -e "\nYou can reset by command:\n"
    echo -e "/usr/local/lsws/admin/misc/admpass.sh"
else
    echo -e "Something went wrong , LSWS can not be started."
    exit 1
fi
