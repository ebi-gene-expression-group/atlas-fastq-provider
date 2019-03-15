# Get FASTQ library path in ENA or ENCODE ENA rule : If the number part is
# greater than 1,000,000 then create an extra subdirectory with numbers
# extracted from the 7th number onwards and zero padded on the left ENCODE
# rule: the path is ${library:0:6}/${library}

get_library_path() {
    local library=$1
    local rootDir=$2
    local forceShortForm=${3:-''} # Abandon extended logic- e.g. for private ArrayExpress submissions

    local subDir=${library:0:6}
    local prefix=
    if ! [[ $subDir =~ "ENC" ]] && [[ -z "$forceShortForm" ]] ; then
        local num=${library:3}
        if [ $num -gt 1000000 ]; then
            prefix="00${library:9}/"
        fi 
    fi
    echo "${rootDir}${subDir}/${prefix}${library}/${library}"
}

# Check a list of variables are set

check_variables() {
    vars=("$@")

    for variable in "${vars[@]}"; do
        local value=${!variable}        
        #if [[ -z ${!variable+x} ]]; then   # indirect expansion here
        if [ -z $value ]; then
            echo "ERROR: $variable not set";
            exit 1
        fi
    done
}

# Check we can sudo to a user

check_sudo() {
    sudoUser=$1

    sudo -u $1 echo "Hi!" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "Couldn't sudo to sudoUser"
        exit 1
    fi
}


# Check we have credentials for SSH

check_ena_ssh() {
    if [ -z "$ENA_SSH_USER" ]; then
        echo "To query or download files from the ENA server using ssh you need to set the environment variable ENA_SSH_USER. This is a user to which you can sudo, and which can SSH to $ENA_SSH_HOST and retrieve files from $ENA_SSH_ROOT_DIR." 1>&2
        return 1
    else
        return 0
    fi
}

# Get a string to sudo as necessary

fetch_ena_sudo_string() {

    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 1
    fi 
    
    # Check if we need to sudo, and if we can

    currentUser=$(whoami)
    if [ $currentUser != $ENA_SSH_USER ]; then
        check_sudo $ENA_SSH_USER
        if [ $? -ne 0 ]; then return 1; fi
        sudoString="sudo -u $ENA_SSH_USER "
    else
        sudoString=""
    fi

    echo $sudoString
}


# Use SSH to check if the file is in ENA. Note that the '-n' is important,
# because any 'while read' loops calling this script use STDIN, which SSH will
# consume otherwise.

check_file_in_ena() {
    local enaFile=$1

    sudoString=$(fetch_ena_sudo_string)
    if [ $? -ne 0 ]; then return 1; fi
    
    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 1
    fi 

    $sudoString ssh -n ${ENA_SSH_HOST} "ls ${enaFile}" > /dev/null 2>&1 
    if [ $? -eq 0 ]; then
        return 0
    else
        echo "${enaFile} not present on ${ENA_SSH_HOST}"
        return 1
    fi
}

# Link local file

link_local_file() {
    
    local sourceFile=$1
    local destFile=$2
    
    check_variables "sourceFile" "destFile"
    
    if [ -e "$sourceFile" ]; then
        ln -s $sourceFile $destFile
    else
        echo "Local file $sourceFile does not exist" 1>&2
        return 1
    fi
}

# Fetch a URI by wget

fetch_file_by_wget() {
    local sourceFile=$1
    local destFile=$2

    check_variables "sourceFile" "destFile"
    
    validate_url $sourceFile
    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo "Downloading $sourceFile to $destFile"
    wget  -nv -c $sourceFile -O $destFile.tmp && mv $destFile.tmp $destFile  
}

# Fetch a file from the ENA to a location

fetch_file_from_ena_over_ssh() {
    local enaFile=$1
    local destFile=$2

    check_variables "enaFile" "destFile"

    # Check we can sudo to the necessary user
    sudoString=$(fetch_ena_sudo_string)
    if [ $? -ne 0 ]; then return 1; fi

    # Convert
    enaPath=$(convert_ena_fastq_to_ssh_path $enaFile)

    # Check file is present at specified location    
    check_file_in_ena $enaPath    
    if [ $? -ne 0 ]; then return 1; fi
    
    # Copy file with sudo'd user as appropriate. Then copy the file to a
    # location with the correct user, and remove the old one. This works, while
    # a 'chown' would not.

    echo "Downloading remote file $enaPath to $destFile over SSH"
    chmod g+w $(dirname ${destFile}) && ($sudoString rsync -ssh -avc ${ENA_SSH_HOST}:$enaPath ${destFile}.tmp > /dev/null) && cp ${destFile}.tmp ${destFile} && rm -f ${destFile}.tmp > /dev/null
    if [ $? -ne 0 ] || [ ! -s ${destFile} ] ; then
        echo "Failed to retrieve $enaPath to ${destFile}" >&2
        return 3
    else 
        echo "Success!"
        return 0
    fi
}

fetch_file_from_ena_over_http() {
    local enaFile=$1
    local destFile=$2

    check_variables "enaFile" "destFile"
    
    # Convert
    local enaPath=$(convert_ena_fastq_to_http_path $enaFile)

    fetch_file_by_wget $enaPath $destFile
}

fetch_library_files_from_ena() {
    
    local $library=$1
    local $outputDirectory=$2
    
    check_variables "library" "outputDirectory"
    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 1
    fi 

    echo "About to retrieve $sepe-END library: $library from ENA ... "

    # Construct library paths for remote and local

    remoteFastqPath=$(get_library_path $library ${ENA_SSH_ROOT_DIR})
    localFastqPath=${outputDirectory}/$(get_library_path $library)

    # Create local directory for FASTQ file - if it doesn't already exist

    localFastqDir=`dirname $localFastqPath`
    mkdir -p $localFastqDir
    chmod g+w $localFastqDir

    # Check if we need to sudo, and if we can

    currentUser=$(whoami)
    if [ $currentUser != $ENA_SSH_USER ]; then
        check_sudo $ENA_SSH_USER
        echo "SSH will be sudo'd as $ENA_SSH_USER"
        sudoString="sudo -u $ENA_SSH_USER "
    else
        sudoString=""
    fi

    # Check for possible extensions and download

    for ext in '_1.fastq.gz' '_2.fastq.gz' '.fastq.gz'; do
        check_file_in_ena ${remoteFastqPath}${ext}
        
        fileStatus=$?
        if [ $fileStatus -eq 0 ]; then
            echo "Found ${ext} file, downloading"
            fetch_file_from_ena_over_ssh ${remoteFastqPath}${ext} ${localFastqPath}${ext}
        fi
    done
}

# Get a list of all the files present for a given library

get_ena_library_files() {
    local library=$1
    local libDir=$(dirname $(get_library_path $library))

    $(fetch_ena_sudo_string) ssh -n ${ENA_SSH_HOST} ls ${ENA_SSH_ROOT_DIR}/$libDir/*
}

# Convert an SRA-style file to its path on the ENA node 

convert_ena_fastq_to_ssh_path(){
    local fastq=$1

    local fastq=$(basename $fastq)
    local library=$(echo $fastq | grep -o "[SED]RR[0-9]*")
    local libDir=$(dirname $(get_library_path $library))

    echo ${ENA_SSH_ROOT_DIR}/$libDir/$fastq
}

# Convert an SRA-style file to its path at the HTTP endpoint 

convert_ena_fastq_to_http_path(){
    local fastq=$1

    local fastq=$(basename $fastq)
    local library=$(echo $fastq | grep -o "[SED]RR[0-9]*")
    local libDir=$(dirname $(get_library_path $library))

    echo ${ENA_HTTP_ROOT_PATH}/$libDir/$fastq
}

# Check a URI is valid

function validate_url(){

    wget -q -S --spider $1 > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "URI $1 is invalid" 1>&2
        return 1
    else 
        echo "Link valid"
    fi
}
