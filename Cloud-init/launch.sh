#!/usr/bin/env bash
CLDINITPATH='/var/lib/cloud/scripts/per-instance'
OSNAME=''
setup ()
{
  if [ -e "${CLDINITPATH}/per-instance.sh" ]; then
    rm -rf ${CLDINITPATH}/per-instance.sh
  fi
  check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
  }
  check_os
  cat << EOF > ${CLDINITPATH}/per-instance.sh
#!/bin/bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2018-2020
# @Version: 1.3
# *********************************************************************/
PANEL=''
PANELPATH=''
EDITION=''
LSDIR='/usr/local/lsws'
CONTEXTPATH="\${LSDIR}/Example"
LSHTTPDCFPATH="\${LSDIR}/conf/httpd_config.conf"
LSEXAMCFPATH="\${LSDIR}/conf/vhosts/Example/vhconf.conf"
CLOUDPERINSTPATH='/var/lib/cloud/scripts/per-instance'
WPCT='noneclassified'
OSNAME=''

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}
check_os

editioncheck() 
{
  if [ -d /usr/local/CyberCP ]; then
    PANEL='cyber'
    PANELPATH='/usr/local/CyberCP'
    LSCPPATH='/usr/local/lscp'
    CPCFPATH="\${PANELPATH}/CyberCP/settings.py"
    CPSQLPATH='/etc/cyberpanel/mysqlPassword'
    CPIPPATH='/etc/cyberpanel/machineIP'
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
  if [ -e \${LSDIR}/bin/openlitespeed ]; then 
    EDITION='openlitespeed'
  elif [ -e \${LSDIR}/bin/litespeed ]; then
    EDITION='litespeed'
  fi  
}
editioncheck

providerck()
{
  if [ "\$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ] && [ -d /home/ubuntu ]; then 
    PROVIDER='aws'
  elif [ "\$(dmidecode -s bios-vendor)" = 'Google' ];then
    PROVIDER='google'      
  elif [ "\$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
    PROVIDER='do'
  else
    PROVIDER='undefined'  
  fi
}
providerck

pathupdate()
{
  if [ "\${PANEL}" = 'cyber' ]; then  
    PHPMYPATH="\${PANELPATH}/public/phpmyadmin"
    WPCT="\${PROVIDER}_ols_cyberpanel"
  elif [ "\${PANEL}" = '' ]; then
    PHPMYPATH='/var/www/phpmyadmin'  
    DOCPATH=\$(grep 'docRoot' \${LSEXAMCFPATH} | awk '{print \$2}')
    echo \${DOCPATH} | grep 'old' > /dev/null
    if [ \$? -eq 0 ]; then
      DOCPATH=\${DOCPATH::-5}
      DOCPATH=\${DOCPATH}/
    fi 
    if [ "\$(echo \${DOCPATH} | grep '\\$')" != '' ]; then
      VHROOTURL=\$(echo \${DOCPATH} | sed 's/\$VH_ROOT\\///')
      DOCPATH="\${LSDIR}/Example/\${VHROOTURL}/"
    fi 
    if [ -f '/usr/bin/node' ] && [ "\$(grep -n 'appType.*node' \${LSEXAMCFPATH})" != '' ]; then
      APPLICATION='NODE'
      WPCT="\${PROVIDER}_ols_node"
    elif [ -f '/usr/bin/ruby' ] && [ "\$(grep -n 'appType.*rails' \${LSEXAMCFPATH})" != '' ]; then
      APPLICATION='RUBY'
      WPCT="\${PROVIDER}_ols_ruby"
    elif [ -f '/usr/bin/python3' ] && [ "\$(grep -n 'appType.*wsgi' \${LSEXAMCFPATH})" != '' ]; then
      APPLICATION='PYTHON'
      CONTEXTPATH="\${LSDIR}/Example/demo/demo/settings.py"
      WPCT="\${PROVIDER}_ols_python"
    else
      APPLICATION='NONE'  
      WPCT="\${PROVIDER}_ols_wordpress"
    fi  
  fi 
  PHPMYCFPATH="\${PHPMYPATH}/config.inc.php"
  if [ -f "\${DOCPATH}/wp-config.php" ]; then 
    WPCFPATH="\${DOCPATH}/wp-config.php"
  fi

}
pathupdate
oshmpath()
{
  if [ \${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
    HMPATH='/home/ubuntu'
    PUBIP=\$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
  elif [ \${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
    HMPATH='/home/ubuntu'
    PUBIP=\$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)    
  else
    HMPATH='/root'
    PUBIP=\$(ifconfig eth0 | grep 'inet '| awk '{printf \$2}')
  fi    
}
oshmpath

doimgversionct()
{ 
  curl "https://wp.api.litespeedtech.com/v?t=image&src=\${WPCT}" > /dev/null 2>&1
}

dbpasswordfile()
{
  if [ ! -e "\${HMPATH}/.db_password" ]; then 
    touch "\${HMPATH}/.db_password"
    DBPASSPATH="\${HMPATH}/.db_password"
  else
    DBPASSPATH="\${HMPATH}/.db_password"
    ori_root_mysql_pass=\$(grep 'root_mysql_pass' \${DBPASSPATH} | awk -F'=' '{print \$2}' | tr -d '"')  
  fi
}
litespeedpasswordfile()
{
  if [ ! -e "\${HMPATH}/.litespeed_password" ]; then 
    touch "\${HMPATH}/.litespeed_password"
  fi
  LSPASSPATH="\${HMPATH}/.litespeed_password"
}
## dovecot
APP_DOVECOT_CF='/etc/dovecot/dovecot-sql.conf.ext'
## postfix
APP_POSTFIX_DOMAINS_CF='/etc/postfix/mysql-virtual_domains.cf'
APP_POSTFIX_EMAIL2EMAIL_CF='/etc/postfix/mysql-virtual_email2email.cf'
APP_POSTFIX_FORWARDINGS_CF='/etc/postfix/mysql-virtual_forwardings.cf'
APP_POSTFIX_MAILBOXES_CF='/etc/postfix/mysql-virtual_mailboxes.cf'

if [ \${OSNAME} = 'ubuntu' ] || [ \${OSNAME} = 'debian' ]; then 
  ## pure-ftpd
  APP_PUREFTP_CF='/etc/pure-ftpd/pureftpd-mysql.conf'
  APP_PUREFTPDB_CF='/etc/pure-ftpd/db/mysql.conf'
  ## powerdns
  APP_POWERDNS_CF='/etc/powerdns/pdns.conf'
elif [ \${OSNAME} = 'centos' ]; then
  ## pure-ftpd
  APP_PUREFTP_CF='/etc/pure-ftpd/pureftpd-mysql.conf'
  APP_PUREFTPDB_CF='/etc/pure-ftpd/pureftpd-mysql.conf'
  ## powerdns
  APP_POWERDNS_CF='/etc/pdns/pdns.conf'
fi

#####################################################################
### Generate cert/key/password ###
genlswspwd()
{
  ADMIN_PASS=\$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
  ENCRYPT_PASS=\$(\${LSDIR}/admin/fcgi-bin/admin_php* -q \${LSDIR}/admin/misc/htpasswd.php \${ADMIN_PASS})
}

gensqlpwd(){
  root_mysql_pass=\$(openssl rand -hex 24)
  wordpress_mysql_pass=\$(openssl rand -hex 24)
  debian_sys_maint_mysql_pass=\$(openssl rand -hex 24)
}
gensaltpwd(){
  GEN_SALT=\$(</dev/urandom tr -dc 'a-zA-Z0-9!@#%^&*()-_[]{}<>~+=' | head -c 64 | sed -e 's/[\/&]/\\&/g')
}
gensecretkey(){
  GEN_SECRET=\$(</dev/urandom tr -dc 'a-zA-Z0-9!@#%^&*()-_[]{}<>~+=' | head -c 50 | sed -e 's/[\/&]/\\&/g')
}
gen_selfsigned_cert()
{  
  # set default value
  SSL_HOSTNAME=webadmin
  csr="\${SSL_HOSTNAME}.csr"
  key="\${SSL_HOSTNAME}.key"
  cert="\${SSL_HOSTNAME}.crt"

  # Create the certificate signing request
  openssl req -new -passin pass:password -passout pass:password -out \${csr} >/dev/null 2>&1 <<csrconf
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
  [ -f \${csr} ] && openssl req -text -noout -in \${csr} >/dev/null 2>&1
# Create the Key
  openssl rsa -in privkey.pem -passin pass:password -passout pass:password -out \${key} >/dev/null 2>&1
# Create the Certificate
  openssl x509 -in \${csr} -out \${cert} -req -signkey \${key} -days 1000 >/dev/null 2>&1
# Remove file
  rm -f \${SSL_HOSTNAME}.csr 
  rm -f privkey.pem
}

### Tools
linechange(){
  LINENUM=\$(grep -n "\${1}" \${2} | cut -d: -f 1)
  if [ -n "\$LINENUM" ] && [ "\$LINENUM" -eq "\$LINENUM" ] 2>/dev/null; then
    sudo sed -i "\${LINENUM}d" \${2}
    sudo sed -i "\${LINENUM}i\${3}" \${2}
  fi  
}

### Update/Renew password/key ###
lscpd_cert_update()
{
  if [ "\${PANEL}" = 'cyber' ]; then
    cp \${SSL_HOSTNAME}.crt \${LSCPPATH}/conf/cert.pem
    cp \${SSL_HOSTNAME}.key \${LSCPPATH}/conf/key.pem
  fi  
}

web_admin_update()
{
  echo "admin:\${ENCRYPT_PASS}" > \${LSDIR}/admin/conf/htpasswd
  echo "admin_pass=\${ADMIN_PASS}" > \${LSPASSPATH}
  mv \${SSL_HOSTNAME}.crt \${LSDIR}/admin/conf/\${SSL_HOSTNAME}.crt
  mv \${SSL_HOSTNAME}.key \${LSDIR}/admin/conf/\${SSL_HOSTNAME}.key
  service lsws restart
}

panel_admin_update()
{
  if [ "\${PANEL}" = 'cyber' ]; then   
    python \${PANELPATH}/plogical/adminPass.py --password \${ADMIN_PASS}
  fi  
}

panel_sshkey_update()
{
  if [ "\${PANEL}" = 'cyber' ]; then
    ssh-keygen -f /root/.ssh/cyberpanel -t rsa -N ''
  fi
}

panel_IP_update()
{
  if [ "\${PANEL}" = 'cyber' ]; then
    echo "\${PUBIP}" > \${CPIPPATH}
  fi
}

filepermission_update(){
  chmod 600 \${HMPATH}/.db_password 
  chmod 600 \${HMPATH}/.litespeed_password
}

updatesecretkey(){
  if [ "\${PANEL}" = 'cyber' ]; then 
    SECRETPATH=\${CPCFPATH}
  elif [ "\${APPLICATION}" = 'PYTHON' ]; then  
    SECRETPATH=\${CONTEXTPATH}  
  fi  
  LINENUM=\$(grep -n 'SECRET_KEY' \${SECRETPATH} | cut -d: -f 1) 
  sed -i "\${LINENUM}d" \${SECRETPATH}
  NEWKEY="SECRET_KEY = '\${GEN_SECRET}'"
  sed -i "\${LINENUM}i\${NEWKEY}" \${SECRETPATH}
}

updateCPsqlpwd(){
  PREPWD=\$(cat \${CPSQLPATH})
### root user 
  mysql -uroot -p\${PREPWD} \\
        -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('\${root_mysql_pass}');"

    for LINENUM in \$(grep -n "'PASSWORD':" \${CPCFPATH} | cut -d: -f 1); 
      do 
        NEWDBPWD="        'PASSWORD': '\${root_mysql_pass}',"
        sed -i "\${LINENUM}s/.*/\${NEWDBPWD}/" \${CPCFPATH}
      done
    sed -i "1s/.*/\${root_mysql_pass}/" \${CPSQLPATH}
### cyberpanel user    
    mysql -uroot -p\${root_mysql_pass} \\
        -e "SET PASSWORD FOR 'cyberpanel'@'localhost' = PASSWORD('\${root_mysql_pass}');"

### update cyberpanel to applications conf files
#### dovecot
  NEWKEY="connect = host=localhost dbname=cyberpanel user=cyberpanel password=\${root_mysql_pass} port=3306"
  linechange 'password=' \${APP_DOVECOT_CF} "\${NEWKEY}"

#### postfix
  NEWKEY="password = \${root_mysql_pass}"
  linechange 'password =' \${APP_POSTFIX_DOMAINS_CF} "\${NEWKEY}"
  linechange 'password =' \${APP_POSTFIX_EMAIL2EMAIL_CF} "\${NEWKEY}"
  linechange 'password =' \${APP_POSTFIX_FORWARDINGS_CF} "\${NEWKEY}"
  linechange 'password =' \${APP_POSTFIX_MAILBOXES_CF} "\${NEWKEY}"

#### pure-ftpd
  NEWKEY="MYSQLPassword \${root_mysql_pass}"
  linechange 'MYSQLPassword' \${APP_PUREFTP_CF} "\${NEWKEY}"
  linechange 'MYSQLPassword' \${APP_PUREFTPDB_CF} "\${NEWKEY}"
  if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then 
      systemctl restart pure-ftpd-mysql.service
  elif [ "${OSNAME}" = 'centos' ]; then 
      service pure-ftpd restart
  fi    
  
#### powerdns
  NEWKEY="gmysql-password=\${root_mysql_pass}"
  linechange 'gmysql-password' \${APP_POWERDNS_CF} "\${NEWKEY}"

### Apply settings
    service lscpd restart
}

renewwppwd(){
  NEWDBPWD="define('DB_PASSWORD', '\${wordpress_mysql_pass}');"
  linechange 'DB_PASSWORD' \${WPCFPATH} "\${NEWDBPWD}"
}


### Listener '*' to 'IP'
replacelitenerip(){
#for LINENUM in \$(grep -n 'map.*Example.*\\*' \${LSHTTPDCFPATH} | cut -d: -f 1)
for LINENUM in \$(grep -n 'map' \${LSHTTPDCFPATH} | cut -d: -f 1)
  do
    NEWDBPWD="  map                     Example \${PUBIP}"
    sed -i "\${LINENUM}s/.*/\${NEWDBPWD}/" \${LSHTTPDCFPATH}
  done  
}

updatesqlpwd(){
mysql -uroot -p\${ori_root_mysql_pass} \\
      -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '\${root_mysql_pass}'"
mysql -uroot -p\${root_mysql_pass} \\
      -e "ALTER USER 'wordpress'@'localhost' IDENTIFIED BY '\${wordpress_mysql_pass}'"
mysql -uroot -p\${root_mysql_pass} \\
      -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost"
mysql -uroot -p\${root_mysql_pass} \\
      -e "ALTER USER 'debian-sys-maint'@'localhost' IDENTIFIED BY '\${debian_sys_maint_mysql_pass}'"

cat > /etc/mysql/debian.cnf <<EOM
# Automatically generated for Debian scripts. DO NOT TOUCH!
[client]
host     = localhost
user     = debian-sys-maint
password = \${debian_sys_maint_mysql_pass}
socket   = /var/run/mysqld/mysqld.sock
[mysql_upgrade]
host     = localhost
user     = debian-sys-maint
password = \${debian_sys_maint_mysql_pass}
socket   = /var/run/mysqld/mysqld.sock
EOM
}

renewwpsalt(){
# WordPress Salts
  for KEY in "'AUTH_KEY'" "'SECURE_AUTH_KEY'" "'LOGGED_IN_KEY'" "'NONCE_KEY'" "'AUTH_SALT'" "'SECURE_AUTH_SALT'" "'LOGGED_IN_SALT'" "'NONCE_SALT'"
  do
    LINENUM=\$(grep -n "\${KEY}" \${WPCFPATH} | cut -d: -f 1)
    sed -i "\${LINENUM}d" \${WPCFPATH}
    NEWSALT="define(\${KEY}, '\${GEN_SALT}');"
    sed -i "\${LINENUM}i\${NEWSALT}" \${WPCFPATH}
  done
}

renewblowfish(){
#phpmyadmin blowfish
  LINENUM=\$(grep -n "'blowfish_secret'" \${PHPMYCFPATH} | cut -d: -f 1)
  sed -i "\${LINENUM}d" \${PHPMYCFPATH}
  NEW_SALT="\\\$cfg['blowfish_secret'] = '\${GEN_SALT}';"
  sed -i "\${LINENUM}i\${NEW_SALT}" \${PHPMYCFPATH}
}

### Update File###
updaterootpwdfile(){
  rm -f \${DBPASSPATH}
  cat >> \${DBPASSPATH} <<EOM
root_mysql_pass="\${root_mysql_pass}"
EOM
}

updateCPpwdfile(){
  rm -f \${DBPASSPATH}
  cat >> \${DBPASSPATH} <<EOM
root_mysql_pass="\${root_mysql_pass}"
cyberpanel_mysql_pass="\${root_mysql_pass}"
EOM
}

updatepwdfile(){
  rm -f \${DBPASSPATH}
  cat >> \${DBPASSPATH} <<EOM
root_mysql_pass="\${root_mysql_pass}"
wordpress_mysql_pass="\${wordpress_mysql_pass}"
EOM
}

### Update software
upgrade_cyberpanel() {
    if [ -e /tmp/upgrade.py ]; then
      sudo rm -rf /tmp/upgrade.py
    fi
    wget --quiet http://cyberpanel.net/upgrade.py
    sudo chmod 755 /tmp/upgrade.py
    sudo python /tmp/upgrade.py
}

###prevent hijacking
afterssh(){
  NEWKEY="docRoot                   \${DOCPATH}"
  linechange 'docRoot' \${LSEXAMCFPATH} "\${NEWKEY}"

  if [ \$(grep 'R.*/index.html.*R' \${LSEXAMCFPATH} | wc -l) -ne '0' ]; then
    LINENUM=\$(grep -n 'R.*/index.html.*R' \${LSEXAMCFPATH} | tail -1 | cut -d: -f 1)
    sudo sed -i "\${LINENUM}d" \${LSEXAMCFPATH}
  fi
  if [ \${PROVIDER} = 'google' ]; then 
      \${HMPATH}='/home/ubuntu'
  fi    
  sudo sed -i '/afterssh.sh/d' /etc/profile
  sudo service lsws restart
}

aftersshsetup(){
  if [ \${PROVIDER} = 'google' ]; then 
      \${HMPATH}='/home/ubuntu'
  fi   
  if [ -e '\${HMPATH}/afterssh.sh' ]; then
    sudo rm -rf \${HMPATH}/afterssh.sh
  fi
 
  sudo cat << EOM > \${HMPATH}/afterssh.sh
#!/bin/bash
source \${CLOUDPERINSTPATH}/per-instance.sh >> /dev/null 2>&1
afterssh
deleteinstancesh -f
sudo rm -f '\${HMPATH}/afterssh.sh'
EOM
sudo chmod a+x \${HMPATH}/afterssh.sh
}

beforessh(){
  if [ -d \${DOCPATH::-1}.old ]; then
    NEWKEY="docRoot                   \${DOCPATH::-1}.old/"
    linechange 'docRoot' \${LSEXAMCFPATH} "\${NEWKEY}"
  fi

  if [ \$(grep 'R.*/index.html.*R' \${LSEXAMCFPATH} | wc -l) -eq '0' ]; then
    NEWKEY='RewriteRule ^(.*)\$ http://%{SERVER_NAME}/index.html [R,L]'
    LINENUM=\$(grep -n '}' \${LSEXAMCFPATH} | tail -1 | cut -d: -f 1)
    sed -i "\${LINENUM}i\${NEWKEY}" \${LSEXAMCFPATH}
  fi  
  sudo service lsws restart
  echo "\${HMPATH}/afterssh.sh" >> /etc/profile
  echo "/opt/domainsetup.sh" >> /etc/profile
}

deleteinstancesh(){
  if [ ! -f \${HMPATH}/afterssh.sh ]; then
    sudo rm -f \${CLOUDPERINSTPATH}/per-instance.sh
  fi
  if [ "\$1" = '-f' ]; then 
    sudo rm -f \${CLOUDPERINSTPATH}/per-instance.sh
  fi
}

addtohosts(){
  if [ -d /home/ubuntu ]; then
    NEWKEY="127.0.0.1 localhost $(hostname)"
    linechange '127.0.0.1' /etc/hosts "${NEWKEY}"
  fi
}

#Security
installfirewalld(){
  FWDCMD='/usr/bin/firewall-cmd --permanent --zone=public --add-rich-rule'

  /usr/bin/apt-get install firewalld -y
  /bin/systemctl enable firewalld

  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="8090" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="8090" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="80" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="80" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="443" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="443" accept'
  /usr/bin/firewall-cmd --add-service=ssh --permanent
  /usr/bin/firewall-cmd --add-service=ftp --permanent
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="25" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="25" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="587" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="587" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="465" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="465" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="110" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="110" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="143" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="143" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="993" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="993" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="udp" port="53" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="udp" port="53" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="53" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="53" accept'
  \${FWDCMD}='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="40110-40210" accept'
  \${FWDCMD}='rule family="ipv6" port protocol="tcp" port="40110-40210" accept'

  /usr/bin/firewall-cmd --reload
}

check_version() {
  VERSION_1=\$1
  OPTION=\$2
  VERSION_2=\$3

  VERSION_1=\${VERSION_1//./ }
  VERSION_2=\${VERSION_2//./ }

  VERSION_1_MAJOR=\$(awk '{print \$1}' <<< "\${VERSION_1}")
  VERSION_1_MINOR=\$(awk '{print \$2}' <<< "\${VERSION_1}")
  VERSION_1_PATCH=\$(awk '{print \$3}' <<< "\${VERSION_1}")

  VERSION_2_MAJOR=\$(awk '{print \$1}' <<< "\${VERSION_2}")
  VERSION_2_MINOR=\$(awk '{print \$2}' <<< "\${VERSION_2}")
  VERSION_2_PATCH=\$(awk '{print \$3}' <<< "\${VERSION_2}")

  if [[ "\${OPTION}" == '>' ]]; then
    if [[ "\${VERSION_1_MAJOR}" -gt "\${VERSION_2_MAJOR}" ]] || [[ "\${VERSION_1_MINOR}" -gt "\${VERSION_2_MINOR}" ]] || [[ "\${VERSION_1_PATCH}" -gt "\${VERSION_2_PATCH}" ]]; then
      return 0
    fi
  elif [[ "\${OPTION}" == '<' ]]; then
    if [[ "\${VERSION_1_MAJOR}" -lt "\${VERSION_2_MAJOR}" ]] || [[ "\${VERSION_1_MINOR}" -lt "\${VERSION_2_MINOR}" ]] || [[ "\${VERSION_1_PATCH}" -lt "\${VERSION_2_PATCH}" ]]; then
      return 0
    fi
  elif [[ "\${OPTION}" == '=' ]]; then
    if [[ "\${VERSION_1_MAJOR}" -eq "\${VERSION_2_MAJOR}" ]] && [[ "\${VERSION_1_MINOR}" -eq "\${VERSION_2_MINOR}" ]] && [[ "\${VERSION_1_PATCH}" -eq "\${VERSION_2_PATCH}" ]]; then
      return 0
    fi
  fi

  return 1
}

update_phpmyadmin() {
  INSTALL_PATH="\${PHPMYPATH}"  
  LOCAL_VERSION=\$(cat \${INSTALL_PATH}/ChangeLog | head -n4 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]')
  LATEST_VERSION=\$(curl -s https://www.phpmyadmin.net/home_page/version.php | head -n1)
  URL="https://files.phpmyadmin.net/phpMyAdmin/\${LATEST_VERSION}/phpMyAdmin-\${LATEST_VERSION}-all-languages.zip"

  if check_version "\${LOCAL_VERSION}" '<' "\${LATEST_VERSION}"; then
    cd /tmp/
    if [ -e "phpMyAdmin-\${LATEST_VERSION}-all-languages.zip" ]; then
      sudo rm -f phpMyAdmin-\${LATEST_VERSION}-all-languages.zip
    fi
    curl -Os \${URL}
    unzip -qq phpMyAdmin-\${LATEST_VERSION}-all-languages.zip
    cp -pr phpMyAdmin-\${LATEST_VERSION}-all-languages/* \${INSTALL_PATH}/
    if [ "\${PANEL}" = 'cyber' ]; then
      USER='root'
      GROUP='root'
      chown -R \${USER}:\${GROUP} \${INSTALL_PATH}/
     else
      USER='www-data'
      GROUP='www-data'      
      chown -R \${USER}:\${GROUP} \${INSTALL_PATH}/  
    fi  
    sudo rm -rf /tmp/phpMyAdmin-\${LATEST_VERSION}-all-languages* 
  fi
}

set_tmp() {
  if ! \$(cat /proc/mounts | grep -q '/dev/loop0 /tmp'); then
    # Create Loop device
    dd if=/dev/zero of=/usr/.tempdisk bs=100M count=15
    mkfs.ext4 /usr/.tempdisk

    # backup data
    mkdir -p /usr/.tmpbak/
    cp -pr /tmp/* /usr/.tmpbak/

    # mount loop
    mount -o loop,rw,nodev,nosuid,noexec,nofail /usr/.tempdisk /tmp

    # make sure permissions are correct
    chmod 1777 /tmp

    # move tmp files back
    cp -pr /usr/.tmpbak/* /tmp/
    rm -rf /usr/.tmpbak

    # bind mount var/tmp
    mount --bind /tmp /var/tmp

    # setup fstab entries
    echo '/usr/.tempdisk /tmp ext4 loop,rw,noexec,nosuid,nodev,nofail 0 0' >> /etc/fstab
    echo '/tmp /var/tmp none bind 0 0' >> /etc/fstab
  fi
}

maincloud(){
    litespeedpasswordfile
    doimgversionct
    genlswspwd
    addtohosts
    gen_selfsigned_cert
    lscpd_cert_update
    web_admin_update
    gensqlpwd
    gensaltpwd
    gensecretkey
    set_tmp
  if [ "\${PANEL}" = 'cyber' ]; then
    dbpasswordfile
    panel_admin_update
    panel_sshkey_update
    panel_IP_update
    update_phpmyadmin
    updateCPsqlpwd
    updatesecretkey
    updateCPpwdfile
    filepermission_update
    renewblowfish
    if [ "\${OSNAME}" != 'centos' ]; then 
        installfirewalld
    fi    
  elif [ "\${APPLICATION}" = 'PYTHON' ]; then
    updatesecretkey
  elif [ "\${APPLICATION}" = 'NONE' ]; then
    dbpasswordfile
    renewwppwd
    updatesqlpwd
    updatepwdfile
    replacelitenerip
    renewwpsalt
    update_phpmyadmin
    renewblowfish
    beforessh
    aftersshsetup
  fi
}

EOF
  if [ -e "${CLDINITPATH}/main-per-instance.sh" ]; then
    rm -f ${CLDINITPATH}/main-per-instance.sh
  fi
  cat << EOM > /var/lib/cloud/scripts/per-instance/main-per-instance.sh
#!/usr/bin/env bash
# /********************************************************************
# LiteSpeed Cloud Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2018-2020
# @Version: 1.3
# *********************************************************************/
. /var/lib/cloud/scripts/per-instance/per-instance.sh
maincloud
deleteinstancesh
rm -f /var/lib/cloud/scripts/per-instance/main-per-instance.sh
EOM

chmod 777 ${CLDINITPATH}/per-instance.sh
chmod 777 ${CLDINITPATH}/main-per-instance.sh
}

cleanup (){
  # IF CyberPanel is installed on Ubuntu we need to remove firewalld
  if [ -d /usr/local/CyberCP ] && [ "${OSNAME}" != 'centos' ]; then
    sudo apt-get remove firewalld -y > /dev/null 2>&1
  fi

  #cloud-init here
  rm -f /var/log/cloud-init.log
  rm -f /var/log/cloud-init-output.log
  rm -rf /var/lib/cloud/data
  rm -rf /var/lib/cloud/instance
  rm -rf /var/lib/cloud/instances/*
  #system log
  rm -rf /var/log/unattended-upgrades
  rm -f /var/log/apt/history.log*
  rm -f /var/log/apt/term.log*
  rm -f /var/log/apt/eipp.log*
  rm -f /var/log/auth.log*
  rm -f /var/log/dpkg.log*
  rm -f /var/log/kern.log*
  rm -f /var/log/ufw.log*
  rm -f /var/log/alternatives.log
  rm -f /var/log/apport.log
  rm -rf /var/log/journal/*
  rm -f /var/log/syslog*
  rm -f /var/log/btmp*
  rm -f /var/log/wtmp*
  rm -f /var/log/yum.log*
  rm -f /var/log/secure
  rm -f /var/log/messages
  rm -f /var/log/dmesg
  rm -f /var/log/audit/audit.log
  rm -f /var/log/maillog
  rm -f /var/tuned/tuned.log
  #aws
  rm -f /var/log/amazon/ssm/*
  #component log
  rm -f /usr/local/lscp/logs/*
  rm -f /var/log/mail.log*
  rm -f /var/log/mail.err
  rm -f /var/log/letsencrypt/letsencrypt.log*
  rm -f /var/log/fail2ban.log* 
  rm -f /var/log/mysql/error.log
  rm -f /etc/mysql/debian.cnf
  rm -f /var/log/redis/redis-server.log
  rm -rf /usr/local/lsws/logs/*
  rm -f /root/.mysql_history
  rm -f /var/log/php*.log
  rm -f /var/log/installLogs.txt
  #Cyberpanel
  rm -f /var/log/anaconda/*
  rm -f /usr/local/lscp/logs/*
  rm -f /usr/local/lscp/cyberpanel/logs/*
  #key
  rm -f /root/.ssh/authorized_keys
  rm -f /root/.ssh/cyberpanel*
  #password
  rm -f /root/.litespeed_password
  if [ "$(cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ] && [ -d /home/ubuntu ]; then
    rm -f /home/ubuntu/.mysql_history
    rm -f /home/ubuntu/.bash_history
    rm -f /home/ubuntu/.ssh/authorized_keys   
    rm -f /home/ubuntu/.litespeed_password
  fi  
  if [ "$(dmidecode -s bios-vendor)" = 'Google' ]; then
    allhmfolder=$(ls /home/)
    for i in ${allhmfolder[@]}; do
      if [ "${i}" != 'ubuntu' ]; then
        rm -rf "/home/${i}"
      fi
    done  
  fi
}

setup
cleanup
rm -- "$0"
exit 0
