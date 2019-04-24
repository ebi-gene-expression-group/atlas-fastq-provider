#!/usr/bin/env bash 

usage() { echo "Usage: $0 -s <source URI>" 1>&2; }

# Parse arguments

while getopts ":s:" o; do
    case "${o}" in
        s)
            s=${OPTARG}
            ;;
        *)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${s}" ]; then
    usage
    exit 1
fi

# Source functions from script directory
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $scriptDir/atlas-fastq-provider-functions.sh

# Re-assign variables for readability

sourceUri=$s

# Run the validatation

validate_url $s 
