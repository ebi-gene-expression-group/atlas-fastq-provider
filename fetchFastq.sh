#!/usr/bin/env bash 

usage() { echo "Usage: $0 [-f <file or uri>] [-t <target file>] [-s <source resource or directory, default 'auto'>] [-m <retrieval method, default 'wget'>] [-p <public or private, default public>] [-l <library, by default inferred from file name>] [-c <config file to override defaults>]" 1>&2; }

# Parse arguments

s=auto
m=auto
p=public
l=

while getopts ":f:t:s:m:p:l:c:" o; do
    case "${o}" in
        f)
            f=${OPTARG}
            ;;
        s)
            s=${OPTARG}
            ;;
        t)
            t=${OPTARG}
            ;;
        m)
            m=${OPTARG}
            ;;
        p)
            p=${OPTARG}
            ;;
        l)
            l=${OPTARG}
            ;;
        c)
            c=${OPTARG}
            ;;
        *)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${f}" ] || [ -z "${s}" ] || [ -z "${t}" ] || [ -z "${m}" ]; then
    usage
    exit 1
fi

# Source functions from script directory
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $scriptDir/atlas-fastq-provider-functions.sh
source $scriptDir/atlas-fastq-provider-config.sh

# Re-assign variables for readability

file_or_uri=$f
target=$t
fileSource=$s
method=$m
status=$p
library=$l
configFile=$c

if [ ! -z "$configFile" ]; then
    source $configFile
fi

# For 'auto', guess the file source in case we need it

if [ "$fileSource" == 'auto' ]; then
    fileSource=$(guess_file_source $file_or_uri)
fi

# Guess the method when set to 'auto'

if [ "$method" == 'auto' ]; then

    if [ "$fileSource" == 'ena' ]; then
        method='ena_auto'
    
    elif [ -d "$fileSource" ]; then
        method='dir'

    # Assume anything else is a URI we can wget

    else
        method='wget'
    fi

elif [ "$method" == 'dir' ]; then
    
    if [ ! -d "$fileSource" ]; then
        echo "$fileSource is not a directory" 1>&2
        exit 7   
    fi

elif [ "$method" != 'wget' ]; then
    
    if [ "$fileSource" == 'ena' ]; then

        if [ "$method" == 'ssh' ] || [ "$method" == 'ftp' ] || [ "$method" == 'http' ];then
            method="ena_$method"
        else
            echo "$method not valid for ENA" 1>&2
            exit 8    
        fi
    
    else
        echo "No special procedures implemented for $fileSource. Please use 'wget' or 'dir'." 
    fi

fi

# Now generate the output file

fetch_status=

if [ "$method" == 'wget' ]; then
    fetch_file_by_wget $file_or_uri $target
    fetch_status=$?    

elif [ "$method" == 'dir' ]; then
    link_local_file $fileSource/$file_or_uri $file_or_uri
    fetch_status=$?    

elif [ "$method" == 'ena_ssh' ]; then
    # Use an SSH connection to retrieve the file
    fetch_file_from_ena_over_ssh $file_or_uri $target $ENA_RETRIES $library $status 
    fetch_status=$?    

elif [ "$method" == 'ena_http' ]; then
    
    # Use the HTTP endpoint to get the file
    fetch_file_from_ena_over_http $file_or_uri $target $ENA_RETRIES $library
    fetch_status=$?    

elif [ "$method" == 'ena_ftp' ]; then
    
    # Use the FTP wget to get the file
    fetch_file_from_ena_over_ftp $file_or_uri $target $ENA_RETRIES $library
    fetch_status=$?    

elif [ "$method" == 'ena_auto' ]; then
    
    # Auto-select the ENA method get the file
    fetch_file_from_ena_auto $file_or_uri $target $ENA_RETRIES
    fetch_status=$?    
else
    echo "Don't know how to get $file_or_uri from $fileSource with $method" 1>&2
    exit 1
fi 

# Return status 

if [ $fetch_status -eq 0 ]; then
    echo "Successfully downloaded $file_or_uri from $fileSource with $method"
else
    echo -n "Failed to download $file_or_uri from $fileSource with $method: " 1>&2
    if [ $fetch_status -eq 2 ]; then
        echo "file already exists" 1>&2
    elif [ $fetch_status -eq 3 ]; then
        echo "$method method not currently working"  1>&2
    elif [ $fetch_status -eq 4 ]; then
        echo "cannot sudo to SSH user"  1>&2
    elif [ $fetch_status -eq 5 ]; then
        echo "location invalid"  1>&2
    elif [ $fetch_status -eq 6 ]; then
        echo "ENA_SSH_USER, can't use SSH"  1>&2
    elif [ $fetch_status -eq 7 ]; then
        echo "$fileSource is not a directory"  1>&2
    else
        echo "download failed"  1>&2
    fi
fi

exit $fetch_status
