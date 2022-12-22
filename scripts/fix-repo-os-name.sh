#!/bin/bash
OSNAMEVER=UNKNOWN
OSNAME=
OSVER=

function check_os
{
    if [ -f /etc/redhat-release ] ; then
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
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        USER='nobody'
        GROUP='nogroup'
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
}


function centos_update_repo_os
{
    echo 'No need to update for CentOS!'
}

function debian_update_repo_os
{
    MARIADB_REPO_PATH='/etc/apt/sources.list.d/mariadb.list'
    if [ -z ${MARIADB_REPO_PATH} ]; then 
        echo "${MARIADB_REPO_PATH} is not found, exist!"; exit 1
    fi    
    REPO_OS="$(awk '{print $(NF-1)}' ${MARIADB_REPO_PATH})"
    if [[ ${REPO_OS} = @(trusty|xenial|bionic|focal|jammy|jessie|stretch|buster|bullseye) ]]; then 
        echo "Existing string on Repo: ${REPO_OS}"
    else
        echo "${REPO_OS} is not on the list, exist!"; exit 1     
    fi
    echo "Replace ${REPO_OS} with ${OSVER}"
    sed -i "s/${REPO_OS}/${OSVER}/g" ${MARIADB_REPO_PATH}
    echo 'Finished'
}

main(){
    check_os
    if [ ${OSNAME} = 'centos' ]; then
        centos_update_repo_os
    else
        debian_update_repo_os
    fi
}

main


