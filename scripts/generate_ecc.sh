#/usr/bin/env bash
letsencrypt_path='/etc/letsencrypt/live/'
CSR_CONF_FILE='csr.conf'
LSDIR='/usr/local/lsws'
EPACE='        '
WWW_DOMAIN=''
DOMAIN=''

check_input(){
    if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
    then
        help_message
        exit 1
    fi
}

echow(){
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}

generate_csr_conf(){
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

    if [ -d $w_path ]
    then
        echo "folder exits: $w_path"
        rm ${w_path}ecc*
        rm ${w_path}*pem
    else
        echo "folder not exits, create path: $w_path"
        mkdir $w_path
    fi

    generate_csr_conf $DOMAIN $WWW_DOMAIN

    openssl ecparam -genkey -name secp384r1 | sudo openssl ec -out ecc.key 2>&1
    #openssl req -new -sha256 -key ecc.key -nodes -out ecc.csr -outform pem -config csr.conf
    openssl req -new -sha256 -key ecc.key -nodes -out ecc.csr -outform pem -config $CSR_CONF_FILE
#    openssl req -new -sha256 -key ecc.key -nodes -out ecc.csr -outform pem >/dev/null 2>&1 <<csrconf
#US
#NJ
#Virtual
#LiteSpeedCommunity
#Testing
#$w_domain
#.
#.
#.
#csrconf
    mkdir -p ${w_webroot}.well-known
    certbot certonly --non-interactive --agree-tos --email $w_email --webroot -w $w_webroot -d $DOMAIN -d $WWW_DOMAIN  --csr ecc.csr 2>&1
    remove_temporary_file
    mv ecc* $w_path
    mv *pem $w_path
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
    ${LSDIR}/bin/lswsctrl stop >/dev/null 2>&1
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws >/dev/null 2>&1    
}


remove_temporary_file(){
    rm ${CSR_CONF_FILE}
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
#while getopts h:d:e:w: flag
while getopts :d:e:w: flag
do
    case "${flag}" in
        d) domain=${OPTARG};;
        e) email=${OPTARG};;
        w) webroot=${OPTARG};;
    esac
done

#check_input $domain $email $webroot


# add --dry-run 
if [ ! -z "${1}" ]
then
    case ${1} in
        -[hH] | -help | --help)
            help_message
            ;;
        -[d])
            #echo domain: $domain 
            #echo email: $email 
            #echo webroot: $webroot
            generate_ecc_ssl_certificate $domain $email $webroot
            restart_lsws
            ;;
        -[r])
            #remove_temporary_file
            restart_lsws
            ;;
        *)
            help_message
            #w_domain="example.com"
            #www_domain $w_domain
            #generate_csr_conf $DOMAIN $WWW_DOMAIN
           ;;
    esac
fi
