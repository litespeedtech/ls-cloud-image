#!/bin/bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2018-2020
# @Version: 1.0
# *********************************************************************/
DOCROOT='/var/www/html.old'
PLUGINLIST="litespeed-cache.zip all-in-one-seo-pack.zip all-in-one-wp-migration.zip google-analytics-for-wordpress.zip jetpack.zip wp-mail-smtp.zip"
THEME='twentynineteen'
USER='www-data'
GROUP='www-data'
WPCONFIG='wordpress'
TEMPFOLDER='/tmp'

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

wordpresscfg()
{
  NEWDBPWD="define( 'DB_NAME', '${WPCONFIG}' );"
  linechange 'DB_NAME' $DOCROOT/wp-config.php "${NEWDBPWD}"
  NEWDBPWD="define( 'DB_USER', '${WPCONFIG}' );"
  linechange 'DB_USER' $DOCROOT/wp-config.php "${NEWDBPWD}"

}

vscheck()
{
    VERSION=$(grep -E "wp_version.*=" $DOCROOT/wp-includes/version.php | cut -d \' -f2)
    echoG "Now wordpress version: $VERSION"
}

bk()
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
        echo "$DOCROOT/wp-config.php not exist, will copy from wp-config-sample.php"
        cp $DOCROOT/wp-config-sample.php $DOCROOT/wp-config.php
        echo "Updating config file"
        wordpresscfg
        echo 'copy wp-config.php'
        cp -rp $DOCROOT/wp-config.php $TEMPFOLDER/
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

mvbk()
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
   chown -R $USER:$GROUP $DOCROOT/
}

main()
{
    vscheck
    bk
    rmoldwp
    getlastwp
    installlatestwp
    installplugin
    mvbk
    cacheenable
    chowner
    vscheck
}
main
rm -- "$0"
exit 0