#!/usr/bin/env bash 

usage() { echo "Usage: $0 [-c <config file to override defaults>]" 1>&2; }

# Parse arguments

s=auto
m=wget
p=public
l=

while getopts ":c:" o; do
    case "${o}" in
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

# Source functions from script directory
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $scriptDir/atlas-fastq-provider-functions.sh
source $scriptDir/atlas-fastq-provider-config.sh

# Re-assign variables for readability

configFile=$c

if [ ! -z "$configFile" ]; then
    source $configFile
fi

probe_ena_methods
