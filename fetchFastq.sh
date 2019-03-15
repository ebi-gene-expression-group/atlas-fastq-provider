#!/usr/bin/env bash 

usage() { echo "Usage: $0 [-f <file or uri>] [-t <target file>] [-s <source resource or directory>] [-m <retrieval method>]" 1>&2; }

# Parse arguments

s=auto
m=wget

while getopts ":f:t:s:m:" o; do
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
file_source=$s
method=$m

if [ -e "$target" ]; then
    echo "Local file name $target already exists"
    exit 1
fi

# Determine the source type

source_type=''

if [[ $file_or_uri =~ ftp.* ]] || [[ $file_or_uri =~ ftp\/\/* ]]; then
    echo "File is an FTP link"
    source_type='ftp'
elif [[ $file_or_uri =~ http.* ]] || [[ $file_or_uri =~ http\/\/* ]]; then
    echo "File is an HTTP link"
    source_type='http'
else
    echo "$file_or_uri does not look like a URI, assuming it's a path" 
    source_type='dir' 
fi 

# With auto, guess the source

if [ "$file_source" == 'auto' ]; then

    source_file=$(basename $file_or_uri)

    echo $target | grep "[EDS]RR[0-9]*" > /dev/null
    if [ $? -eq 0 ]; then
        echo "File is ENA-type"
        file_source=ena
    else
        echo "Cannot determine source for $file_or_uri, we're just going to assume we can wget it (URLs) or link it (file system locations)"
    fi
fi

# Now generate the output file

if [ "$source_type" == 'dir' ]; then
    link_local_file $file_source/$file_or_uri $file_or_uri
    if [ $? -ne 0 ]; then
        exit 1
    fi
else 
    if [ "$method" == 'wget' ]; then
        fetch_file_by_wget $file_or_uri $target
        if [ $? -ne 0 ]; then
            exit 1
        fi
    elif [ "$file_source" == 'ena' ]; then
        if [ "$method" == 'ssh' ]; then
            # Use an SSH connection to retrieve the file
            fetch_file_from_ena_over_ssh $file_or_uri $target
            if [ $? -ne 0 ]; then
                exit 1
            fi
        
        elif [ "$method" == 'http' ]; then
            
            # Use the HTTP endpoint to get the file
            fetch_file_from_ena_over_http $file_or_uri $target
            
            if [ $? -ne 0 ]; then
                exit 1
            fi
        fi 
    else
        echo "Don't know how to get $file_or_uri from $file_source with $method" 1>&2
        exit 1
    fi 
fi

