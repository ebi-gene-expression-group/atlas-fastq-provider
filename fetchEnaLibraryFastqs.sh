#!/usr/bin/env bash 

usage() { echo "Usage: $0 -l <library, by default inferred from file name> -d <output directory> [-m <retrieval method, default 'wget'>] [-s <source directory for method 'dir'>] [-p <public or private, default public>] [-c <config file to override defaults>]" 1>&2; }

# Parse arguments

l=
d=
m=auto
s=
p=public

while getopts ":l:d:m:s:p:c:" o; do
    case "${o}" in
        l)
            l=${OPTARG}
            ;;
        d)
            d=${OPTARG}
            ;;
        m)
            m=${OPTARG}
            ;;
        s)
            s=${OPTARG}
            ;;
        p)
            p=${OPTARG}
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

if [ -z "${l}" ] || [ -z "${d}" ]; then
    usage
    exit 1
fi

# Source functions from script directory
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $scriptDir/atlas-fastq-provider-functions.sh
source $scriptDir/atlas-fastq-provider-config.sh

# Re-assign variables for readability

library=$l
outputDir=$d
method=$m
fileSource=$s
status=$p
configFile=$c

if [ ! -z "$configFile" ]; then
    source $configFile
fi

if [ "$method" == 'dir' ]; then
    link_local_dir "$fileSource" "$outputDir"
else
    fetch_library_files_from_ena $library $outputDir $ENA_RETRIES $method $status
fi

fetchStatus=$?

# Return status 

if [ $fetchStatus -eq 0 ]; then
    echo "Successfully downloaded $library from ENA with $method"
elif [ $fetchStatus -eq 2 ]; then 
    echo  "Skipped download of already existing $library files from ENA with $method: " 
else
    echo -n "Failed to download $library files from ENA with $method: " 
    if [ $fetchStatus -eq 3 ]; then
        echo "$method method not currently working"
    elif [ $fetchStatus -eq 4 ]; then
        echo "cannot sudo to SSH user"
    elif [ $fetchStatus -eq 5 ]; then
        echo "location invalid"
    elif [ $fetchStatus -eq 6 ]; then
        echo "ENA_SSH_USER, can't use SSH"
    else
        echo "download failed"
    fi
fi

exit $fetchStatus
