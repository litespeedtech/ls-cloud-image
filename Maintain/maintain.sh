#!/bin/bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2018-2020
# @Version: 1.0
# *********************************************************************/
DOCROOT='/var/www/html.old'
LSDIR='/usr/local/lsws'
if [ -e "${LSDIR}/conf/vhosts/wordpress/vhconf.conf" ]; then
    LSVHCFPATH="${LSDIR}/conf/vhosts/wordpress/vhconf.conf"
else
    LSVHCFPATH="${LSDIR}/conf/vhosts/Example/vhconf.conf"
fi
PLUGINLIST="litespeed-cache.zip all-in-one-seo-pack.zip all-in-one-wp-migration.zip google-analytics-for-wordpress.zip jetpack.zip wp-mail-smtp.zip"
THEME='twentynineteen'
USER='www-data'
GROUP='www-data'
WPCONFIG='wordpress'
TEMPFOLDER='/tmp'
PANEL=''

check_os()
{
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}
check_os

check_type(){
    if [ -d /usr/local/CyberCP ]; then
        PANEL='cyber'
    else
        if [ -f '/usr/bin/node' ] && [ "$(grep -n 'appType.*node' ${LSVHCFPATH})" != '' ]; then
            APPLICATION='NODE'
        elif [ -f '/usr/bin/ruby' ] && [ "$(grep -n 'appType.*rails' ${LSVHCFPATH})" != '' ]; then
            APPLICATION='RUBY'
        elif [ -f '/usr/bin/python3' ] && [ "$(grep -n 'appType.*wsgi' ${LSVHCFPATH})" != '' ]; then
            APPLICATION='PYTHON'
        else
            APPLICATION='NONE' 
        fi     
    fi    
}

echoG()
{
    FLAG=$1
    shift
    echo -e "\033[38;5;71m$FLAG\033[39m$@"
}

echoR()
{
    FLAG=$1
    shift
    echo -e "\033[38;5;203m$FLAG\033[39m$@"
}

linechange(){
  LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
  if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
    sudo sed -i "${LINENUM}d" ${2}
    sudo sed -i "${LINENUM}i${3}" ${2}
  fi
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
    echoG 'Finish system update'
}

wpdocrevover(){
    if [ -d /var/www/html/ ] && [ -d /var/www/html.land/ ]; then  
        mv /var/www/html/ ${DOCROOT}/
        mv /var/www/html.land/ /var/www/html/
        service lsws restart
    fi    
}

vscheck()
{
    VERSION=$(grep -E "wp_version.*=" $DOCROOT/wp-includes/version.php | cut -d \' -f2)
    echoG "Now wordpress version: $VERSION"
}

bkwpconfig()
{
    if [ -f $DOCROOT/wp-content/plugins/litespeed-cache/data/const.default.ini ]; then
        echoG "copy const.default.ini"
        cp -rp $DOCROOT/wp-content/plugins/litespeed-cache/data/const.default.ini $TEMPFOLDER/
    else
        echoR "$DOCROOT/wp-content/plugins/litespeed-cache/data/const.default.ini not exist"
    fi

    if [ -f $DOCROOT/wp-config.php ]; then
        echoG 'copy wp-config.php'
        cp -rp $DOCROOT/wp-config.php $TEMPFOLDER/
    else
        echoE "$DOCROOT/wp-config.php not exist"
    fi
}

rmoldwp()
{
    echoG "Remove previous wordpress site"
    rm -rf $DOCROOT/*
}

getlastwp()
{
    rm -f $DOCROOT/latest*
    wget -q -P $DOCROOT/ https://wordpress.org/latest.tar.gz
    if [ $? = 0 ]; then
        echoG "Download WordPress success"
    else
        echoR "Download WordPress FAILED"
    fi
}
installlatestwp()
{
    tar -zxvf $DOCROOT/latest.tar.gz -C $DOCROOT/ >>/dev/null 2>&1
    rm -f $DOCROOT/latest.*
    mv $DOCROOT/wordpress/* $DOCROOT/
    rm -rf $DOCROOT/wordpress/
}
installplugin()
{
    for PLUGIN in $PLUGINLIST; do
        echoG "Install $PLUGIN"
        wget -q -P $DOCROOT/wp-content/plugins/ https://downloads.wordpress.org/plugin/$PLUGIN
        if [ $? = 0 ]; then
            unzip -qq -o ${DOCROOT}/wp-content/plugins/${PLUGIN} -d ${DOCROOT}/wp-content/plugins/
        else
            echoR "$PLUGINLIST FAILED to download"
        fi
    done
    rm -f $DOCROOT/wp-content/plugins/*.zip
}

mvwpconfigbk()
{
    if [ -f $TEMPFOLDER/const.default.ini ]; then
        echoG 'mv back const.default.ini'
        mv $TEMPFOLDER/const.default.ini $DOCROOT/wp-content/plugins/litespeed-cache/data/
    else
        echoR "$TEMPFOLDER/const.default.ini no exist"
    fi

    if [ -f $TEMPFOLDER/wp-config.php ]; then
        echoG 'mv back wp-config.php'
        mv $TEMPFOLDER/wp-config.php $DOCROOT/wp-config.php
    else
        echoR "$TEMPFOLDER/wp-config.php no exist"
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

cacheenable()
{
    cp $DOCROOT/wp-content/themes/$THEME/functions.php $DOCROOT/wp-content/themes/$THEME/functions.php.bk
cked
ed $DOCROOT/wp-content/themes/$THEME/functions.php << END >>/dev/null 2>&1
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

}

chowner()
{
   chown -R $USER:$GROUP /var/www/
}

cyberupgrade(){
    echoG 'Start updating cyberpanel'
    cd
    rm -f upgrade.py
    wget http://cyberpanel.net/upgrade.py
    python upgrade.py
    echoG 'Finish cyberpanel update'
}

wpupgrademain()
{
    echoG 'Start updating wordpress'
    wpdocrevover
    vscheck
    bkwpconfig
    rmoldwp
    getlastwp
    installlatestwp
    installplugin
    mvwpconfigbk
    cacheenable
    chowner
    vscheck
    echoG 'Finish wordpress update'
}

main(){
    systemupgrade
    if [ ${PANEL} = 'cyber' ]; then 
        cyberupgrade
    else     
        if [ ${APPLICATION} = 'NODE' ]; then 
            echo 'Do nothing'
        elif [ ${APPLICATION} = 'RUBY' ]; then 
            echo 'Do nothing'
        elif [ ${APPLICATION} = 'PYTHON' ]; then 
            echo 'Do nothing'
        elif [ ${APPLICATION} = 'NONE' ]; then 
            wpupgrademain
        fi    
    fi
}    

rm -- "$0"
exit 0