#!/usr/bin/env bash 

usage() { echo "Usage: $0 [-f <file or uri>] [-t <target file>] [-s <source resource or directory, default 'auto'>] [-m <retrieval method, default 'wget'>] [-p <public or private, default public>] [-l <library, by default inferred from file name>] [-c <config file to override defaults>] [-v <validate only, don't download>] [-d <download type, fastq or srr>]" 1>&2; }

# Parse arguments

s=auto
m=auto
p=public
l=
v=
d=fastq

while getopts ":f:t:s:m:p:l:c:v:d:" o; do
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
        v)
            v=${OPTARG}
            ;;
        d)
            d=${OPTARG}
            ;;
        *)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${f}" ] || [ -z "${s}" ] || [ -z "${m}" ]; then
    usage
    exit 1
fi

# Source functions from script directory
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $scriptDir/atlas-fastq-provider-functions.sh

config=$scriptDir/atlas-fastq-provider-config.sh
defaultConfig=$scriptDir/atlas-fastq-provider-config.sh.default

if [ ! -e $config ]; then
    cp $defaultConfig $config
fi
source $config

# Re-assign variables for readability

file_or_uri=$f
target=$t
fileSource=$s
method=$m
status=$p
library=$l
configFile=$c
validateOnly=$v
downloadType=$d

if [ -z "$target" ]; then
    target=$(basename $file_or_uri)
fi

if [ ! -z "$configFile" ]; then
    source $configFile
fi

# For 'auto', guess the file source in case we need it

guessedSource=$(guess_file_source $file_or_uri)

# If source is determined as HCA allow it to override specified method

if [[  "$guessedSource" == 'hca' || ( "$fileSource" == 'auto' && "$status" != 'private' ) ]]; then
    fileSource=$guessedSource
fi

# Guess the method when set to 'auto', set to AWS S3 for private

if [ "$status" == 'private' ]; then 

    method='ena_s3'
    fileSource='ena'

elif [ "$fileSource" == 'hca' ]; then

    method='hca'

elif [ "$method" == 'auto' ]; then

    if [ "$fileSource" == 'ena' ] || [ "$fileSource" == 'sra' ]; then
        method='ena_auto'

    elif [ -d "$fileSource" ]; then
        method='dir'

    # Assume anything else is a URI we can wget

    else
        method='wget'
    fi

elif [ "$method" != 'wget' ]; then
    
    if [ "$fileSource" == 'ena' ]; then

        if [ "$method" == 's3' ] || [ "$method" == 'ssh' ] || [ "$method" == 'ftp' ] || [ "$method" == 'http' ];then
            method="ena_$method"
        else
            echo "$method not valid for ENA" 1>&2
            exit 8    
        fi
    
    elif [ "$fileSource" != 'sra' ]; then
        echo "No special procedures implemented for $fileSource file source, should be 'wget' or 'dir'. Falling back to wget." 
        method='wget'
    fi

fi

# Now generate the output file

fetch_status=

# For SRA has a special method, in that it will unpack an SRA file, but we'll
# pass the method through for the downloading of that SRA file

if [ "$fileSource" == 'sra' ]; then

    fetch_file_by_sra $file_or_uri $target "" $m
    fetch_status=$?

elif [ "$method" == 'hca' ]; then
    fetch_file_by_hca $file_or_uri $target
    fetch_status=$?

elif [ "$method" == 'wget' ]; then
    fetch_file_by_wget $file_or_uri $target
    fetch_status=$?    

elif [ "$method" == 'dir' ]; then
    link_local_file $fileSource $file_or_uri $target
    fetch_status=$?

elif [ "$method" == 'ena_ssh' ]; then
    # Use an SSH connection to retrieve the file
    fetch_file_from_ena_over_ssh $file_or_uri $target "$ENA_RETRIES" "$library" "$validateOnly" "$downloadType" $status
    fetch_status=$?

elif [ "$method" == 'ena_s3' ]; then
    # Use AWS S3 to retrieve the file
    fetch_file_from_ena_over_s3 $file_or_uri $target "$ENA_RETRIES" "$library" "$validateOnly" "$downloadType" $status
    fetch_status=$?

elif [ "$method" == 'ena_http' ]; then
    
    # Use the HTTP endpoint to get the file
    fetch_file_from_ena_over_http $file_or_uri $target "$ENA_RETRIES" "$library" "$validateOnly" "$downloadType"
    fetch_status=$?    

elif [ "$method" == 'ena_ftp' ]; then
    
    # Use the FTP wget to get the file
    fetch_file_from_ena_over_ftp $file_or_uri $target "$ENA_RETRIES" "$library" "$validateOnly" "$downloadType"
    fetch_status=$?    

elif [ "$method" == 'ena_auto' ]; then
    
    # Auto-select the ENA method get the file
    fetch_file_from_ena_auto $file_or_uri $target "$ENA_RETRIES" "$library" "$validateOnly" "$downloadType"
    fetch_status=$?    
else
    echo "Don't know how to get $file_or_uri from $fileSource with $method" 1>&2
    exit 1
fi 

# Return status 

action='download'
actioned='downloaded'
if [ -n "$validateOnly" ]; then
    action='validate'
    actioned='validated'
fi

if [[ $fetch_status -eq 0  && ( -s "$target" ||  -n "$validateOnly" ) ]]; then
    echo "Successfully ${actioned} $file_or_uri from $fileSource with $method"
else
    echo -n "Failed to $action $file_or_uri from $fileSource with $method: " 1>&2
    if [ $fetch_status -eq 0 ]; then
        echo "exit status was 0, but $target does not exist"
        fetch_status=1
    elif [ $fetch_status -eq 2 ]; then
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
    elif [ $fetch_status -eq 8 ]; then
        echo "Probable malformed HCA command" 1>&2
    elif [ $fetch_status -eq 9 ]; then
        echo "SRA file retrieval issue" 1>&2
    elif [ $fetch_status -eq 10 ]; then
        echo "ENA_S3_PROFILE needed, can't use AWS S3"
    else
        echo "download failed"  1>&2
    fi
fi

exit $fetch_status
