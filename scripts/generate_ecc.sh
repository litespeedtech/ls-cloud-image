#/usr/bin/env bash
letsencrypt_path='/etc/letsencrypt/live/'
CSR_CONF_FILE='csr.conf'
LSDIR='/usr/local/lsws'
EPACE='        '
WWW_DOMAIN=''
DOMAIN=''
LOG_FILE='/tmp/ecc.log'

check_input(){
    if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
    then
        help_message
        exit 1
    fi
}


domainverify(){
    curl -Is http://${DOMAIN}/ | grep -i 'LiteSpeed\|cloudflare' >> $LOG_FILE 2>&1
    if [ ${?} = 0 ]; then
        echoG "[OK] ${DOMAIN} is accessible."
        TYPE=1
        curl -Is http://${WWW_DOMAIN}/ | grep -i 'LiteSpeed\|cloudflare' >> $LOG_FILE 2>&1
        if [ ${?} = 0 ]; then
            echoG "[OK] ${WWW_DOMAIN} is accessible."
            TYPE=2
        else
            echo "${WWW_DOMAIN} is inaccessible." 
        fi        
    else
        echo "${DOMAIN} is inaccessible, please verify!"; exit 1
    fi
}


echow(){
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}


echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}


generate_csr_conf_two_domains(){
echo "[ req ]
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C=US
ST=NJ
L=Virtual
O=LiteSpeedCommunity
OU=Testing
CN=$DOMAIN

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $DOMAIN
DNS.2 = $WWW_DOMAIN
" >> $CSR_CONF_FILE
}


generate_ecc_ssl_certificate(){
    w_domain=${1}
    w_email=${2}
    w_webroot=${3}
    w_path=$letsencrypt_path${w_domain}/

    # get the $DOMAIN and $WWW_DOMAIN 
    www_domain $w_domain

    # get TYPE1:(one domain) and TYPE2:(two domains)
    domainverify

    if [ -d $w_path ]
    then
        echo "folder exits: $w_path"
        rm ${w_path}ecc* >> $LOG_FILE 2>&1
        rm ${w_path}*pem >> $LOG_FILE 2>&1
    else
        echo "folder not exits, create path: $w_path"
        mkdir -p  $w_path
    fi

    if [ ${TYPE} = 1 ]; then
        openssl ecparam -genkey -name secp384r1 | sudo openssl ec -out ecc.key >> $LOG_FILE 2>&1
        openssl req -new -sha256 -key ecc.key -nodes -out ecc.csr -outform pem >> $LOG_FILE 2>&1 <<csrconf
US
NJ
Virtual
LiteSpeedCommunity
Testing
$w_domain
.
.
.
csrconf
        certbot certonly --non-interactive --agree-tos --email $w_email --webroot -w $w_webroot -d $DOMAIN --csr ecc.csr 
    elif [ ${TYPE} = 2 ]; then
        openssl ecparam -genkey -name secp384r1 | sudo openssl ec -out ecc.key >> $LOG_FILE 2>&1
        generate_csr_conf_two_domains $DOMAIN $WWW_DOMAIN >> $LOG_FILE 2>&1
        openssl req -new -sha256 -key ecc.key -nodes -out ecc.csr -outform pem -config $CSR_CONF_FILE >> $LOG_FILE 2>&1
        certbot certonly --non-interactive --agree-tos --email $w_email --webroot -w $w_webroot -d $DOMAIN -d $WWW_DOMAIN  --csr ecc.csr
    else
        echo 'Unknown type!'; exit 2    
    fi

    remove_temporary_file
    mv ecc* $w_path >> $LOG_FILE 2>&1
    mv *pem $w_path >> $LOG_FILE 2>&1
    echow "SSLCertificateFile /etc/letsencrypt/live/{DOMAIN}/0001_chain.pem"
    echow "SSLCertificateKeyFile /etc/letsencrypt/live/{DOMAIN}/ecc.key"
    
}


help_message(){
    echo -e "\033[1mNAME\033[0m"
    echow "generate_ecc.sh - Generate ECC(elliptical curve cryptography) ECDSA"
    echo -e "\033[1mOPTIONS\033[0m"
    echow '-d'
    echo "${EPACE}${EPACE}Domain"
    echow '-e'
    echo "${EPACE}${EPACE}Email"
    echow '-w'
    echo "${EPACE}${EPACE}Website root folder"
    echow '-h, --help'
    echo "${EPACE}${EPACE}Display help."
    echo -e "\033[1mEXAMPLE\033[0m"
    echow "generate_ecc.sh -d 'example.com' -e 'john@email.com' -w '/var/www/public_html/'"
    echo -e "\033[1mvhost settings\033[0m"
    echow "SSLCertificateFile /etc/letsencrypt/live/{DOMAIN}/0001_chain.pem"
    echow "SSLCertificateKeyFile /etc/letsencrypt/live/{DOMAIN}/ecc.key"
}


restart_lsws(){
    ${LSDIR}/bin/lswsctrl stop >> $LOG_FILE 2>&1
    systemctl stop lsws >> $LOG_FILE 2>&1
    systemctl start lsws >> $LOG_FILE 2>&1
}


remove_temporary_file(){
    rm ${CSR_CONF_FILE} >> $LOG_FILE 2>&1
}

www_domain(){
    CHECK_WWW=$(echo ${1} | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]] ; then
        DOMAIN=$(echo ${1} | cut -c 5-)
    else
        DOMAIN=${1}
    fi
    WWW_DOMAIN="www.${DOMAIN}"
}


# main
while getopts :d:e:w: flag
do
    case "${flag}" in
        d) domain=${OPTARG};;
        e) email=${OPTARG};;
        w) webroot=${OPTARG};;
    esac
done

check_input $domain $email $webroot

if [ ! -z "${1}" ]
then
    case ${1} in
        -[hH] | -help | --help)
            help_message
            ;;
        -[d])
            generate_ecc_ssl_certificate $domain $email $webroot
            restart_lsws
            ;;
        *)
            help_message
           ;;
    esac
fi
