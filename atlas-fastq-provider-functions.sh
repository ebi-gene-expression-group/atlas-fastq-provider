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
    echo "${rootDir}/${subDir}/${prefix}${library}/${library}"
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
        return 1
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

# Get the current temp dir

get_temp_dir() {
    
    local tempdir='tmp'
    if [ "$FASTQ_PROVIDER_TEMPDIR" != '' ]; then
        tempdir="$FASTQ_PROVIDER_TEMPDIR"
    fi
    mkdir -p $tempdir
    echo $tempdir
}

# Calculate how long it's been since a file was modified

file_age() {
    local testfile=$1
    local units=${2:-'millis'}

    check_variables 'testfile'

    local ageInNanos=$(($(date +%s%N) - $(date -r $testfile "+%s%N")))

    if [ "$units" == 'nanos' ]; then
        echo $ageInNanos
    elif [ "$units" == 'millis' ]; then
        echo $(bc -l <<< "scale=2; $ageInNanos / 1000000")
    elif [ "$units" == 'secs' ]; then
        echo $(bc -l <<< "scale=2; $ageInNanos / 1000000000")
    elif [ "$units" == 'mins' ]; then
        echo $(bc -l <<< "scale=2; $ageInNanos / 1000000000/ 60")
    else
        echo "Invalid unit '$units'"
        return 1
    fi
}

# Get the number of milliseconds since a given action was undertaken, marked by a file

time_since_last() {
    local action=$1
    
    check_variables 'action'

    local tempdir=$(get_temp_dir)
    local testfile=$tempdir/${action}.txt
    
    if [ -e "$testfile" ]; then
        file_age $testfile 
        return 0
    else 
        # Just a really big number
        echo 1000000000000
        return 1
    fi
}

# Use a dummy file to mark time since an action was undertaken

record_action() {
    local action=$1
    
    check_variables 'action'

    local tempdir=$(get_temp_dir)
    local testfile=$tempdir/${action}.txt

    touch $testfile
}

# Try not to DDOS resources. Wait until the last action of this type was at least
# $FETCH_FREQ_MILLIS milliseconds ago, then record the pending action to inform
# the next process

wait_and_record() {

    local action=$1

    check_variables 'action'
    
    local last_time=$(time_since_last $action)
    while [ $? -ne 0 ] || (( $(echo "$last_time < $FETCH_FREQ_MILLIS" |bc -l) )); do
        # Sleep for 1/100th of a second
        usleep 10000 

        # Check last_time again- other processes could have altered it
        last_time=$(time_since_last $action)
    done
    
    record_action $action
}

# Fetch a URI by wget

fetch_file_by_wget() {
    local sourceFile=$1
    local destFile=$2
    local retries=${3:-3}
    local method=${4:-''}
    local source=${5:-''}

    check_variables "sourceFile" "destFile"
    
    # Check destination file not already present

    if [ -e "$destFile" ]; then
        return 2
    fi
    
    # Check that the URI is valid

    validate_url $sourceFile
    if [ $? -ne 0 ]; then
        return 5
    fi

    # If the source is $ENA, check the method is currently working 
    
    if [ "$source" == 'ena' ]; then
        check_ena_method $method
        if [ $? -ne 0 ]; then
            return 3
        fi
    fi

    # All being well proceed with the download

    echo "Downloading $sourceFile to $destFile using wget"
    local process_status=1
    for i in $(seq 1 $retries); do 
        if [ "$method" != '' ]; then
            wait_and_record ${source}_$method
        fi

        wget  -nv -c $sourceFile -O $destFile.tmp 
        if [ $? -eq 0 ]; then
            process_status=0
            break
        fi
    done
    
    if [ $process_status -ne 0 ] || [ ! -s ${destFile}.tmp ] ; then
        echo "Failed to retrieve $enaPath to ${destFile}" >&2
        return 1
    else
        mv $destFile.tmp $destFile
    fi
}

# Probe available ENA download methods and determine response times

probe_ena_methods() {

    local tempdir=$(get_temp_dir)
    local probe_file=$tempdir/fastq_provider.probe
    echo -e "method\tresult\tstatus\telapsed_time\tdownload_speed" >> ${probe_file}.tmp

    for method in http ftp ssh; do
        echo "Testing method $method..."
        local function="fetch_file_from_ena_over_$method"
        local start_time=$SECONDS
        $function $ENA_TEST_FILE $tempdir/temp.fq.gz
        local status=$?
        local elapsed_time=$(($SECONDS - $start_time))
    
        local result=success
        local download_speed=NA
        if [ "$status" -ne 0 ]; then
            result=failure
        else
            local test_file_size=$(stat --printf="%s" $tempdir/temp.fq.gz)
            download_speed=$(bc -l <<< "scale=2; $test_file_size / 1000000 / $elapsed_time")
        fi
        echo -e "$method\t$result\t$status\t$elapsed_time\t$download_speed" >> ${probe_file}.tmp
        rm -f $tempdir/temp.fq.gz
    done    

    mv ${probe_file}.tmp ${probe_file}
    echo "ENA retrieval probe results at $tempdir/fastq_provider.probe"
}

# Update the probe if it's got too old

update_ena_probe() {

    local probe_file=$tempdir/fastq_provider.probe

    if [ ! -e $probe_file ]; then
        probe_ena_methods > /dev/null 2>&1
    fi

    local probe_age=$(file_age $probe_file mins)

    if (( $(echo "$probe_age > $PROBE_UPDATE_FREQ_MINS" |bc -l) )); then
        echo "Probe file is older than $PROBE_UPDATE_FREQ_MINS mins (at $probe_age mins), updating" 1>&2
        # Touch to stop other processes from noticing it's out of date
        touch $probe_file
        probe_ena_methods > /dev/null 2>&1
        touch $probe_file 
    fi
}

# Check a particular method is operational according to the probe

check_ena_method() {

    local method=$1

    check_variables 'method'

    local tempdir=$(get_temp_dir)
    local probe_file=$tempdir/fastq_provider.probe

    update_ena_probe
    local method_status=$(tail -n +2 $probe_file | awk '$1=="'$method'"' | awk '{print $5}')

    if [ "$method_status" == 'NA' ]; then
        return 1
    else
        return 0
    fi
}

# Select an ENA download method based on probed response time

select_ena_download_method() {
    
    local tempdir=$(get_temp_dir)
    local probe_file=$tempdir/fastq_provider.probe
    update_ena_probe

    local ordered_methods='None'

    while read -r l; do
        local method=$(echo -e "$l" | awk '{print $1}')
        local result=$(echo -e "$l" | awk '{print $2}')
        local status=$(echo -e "$l" | awk '{print $3}')
        local elapsed_time=$(echo -e "$l" | awk '{print $4}')
        local download_speed=$(echo -e "$l" | awk '{print $5}')
    
        if [ "$ordered_methods" == 'None' ]; then
            ordered_methods=$method
        else
            ordered_methods="$ordered_methods $method"
        fi
    done <<< "$(tail -n +2 $probe_file | awk '$5!="NA"' | sort -k 5,5rn)"

    if [ "$ordered_methods" == 'None' ]; then
        return 1
    else
        echo $ordered_methods
        return 0
    fi
}

# Fetch file from ENA, trying methods in sequence

fetch_file_from_ena_auto() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}

    check_variables "enaFile" "destFile"
    
    # Check destination file not already present

    if [ -e "$destFile" ]; then
        return 2
    fi

    local methods=$(select_ena_download_method)

    if [ $? -ne 0 ]; then
        echo "No ENA download methods available"
        return 3
    fi

    for i in $(seq 1 $retries); do 
        for method in $methods; do
            echo "Fetching $enaFile using method $method, attempt $i"
            function="fetch_file_from_ena_over_$method"
            $function $enaFile $destFile 1  
            
            response=$?
            if [ $response -eq 0 ]; then 
                break 2
            else 
                echo "Failed to retrieve $enaFile using method $method, attempt $i"
            fi
        done    
    done
}

# Fetch a file from the ENA to a location

fetch_file_from_ena_over_ssh() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}
    local status=${5:-'public'}

    check_variables "enaFile" "destFile"

    # Check destination file not already present

    if [ -e "$destFile" ]; then
        return 2
    fi

    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 6
    fi 
    
    check_ena_method 'ssh'
    if [ $? -ne 0 ]; then
        return 3
    fi

    # Check we can sudo to the necessary user
    sudoString=$(fetch_ena_sudo_string)
    if [ $? -ne 0 ]; then return 4; fi

    # Convert to an ENA path
    enaPath=$(convert_ena_fastq_to_ssh_path $enaFile $status $library)

    # Check file is present at specified location    
    check_file_in_ena $enaPath    
    if [ $? -ne 0 ]; then return 5; fi
    
    # Make destination group-writable if we need to sudo
    
    if [ "$sudoString" != '' ]; then
        chmod g+w $(dirname ${destFile})
    fi

    echo "Downloading remote file $enaPath to $destFile over SSH"
    
    # Run the rsync over SSH, sudo'ing if necessary use wait_and_record() to
    # avoid overloading the server

    local process_status=1
    for i in $(seq 1 $retries); do 
        
        wait_and_record 'ena_ssh'
    
        $sudoString rsync -ssh -avc ${ENA_SSH_HOST}:$enaPath ${destFile}.tmp > /dev/null
        if [ $? -eq 0 ]; then
            process_status=0
            break
        fi
    done    

    if [ $process_status -ne 0 ] || [ ! -s ${destFile}.tmp ] ; then
        echo "Failed to retrieve $enaPath to ${destFile}" >&2
        return 1
    fi

    # Move or copy files to final locations

    if [ "$sudoString" != '' ]; then
        $sudoString chmod a+r ${destFile}.tmp
        cp ${destFile}.tmp ${destFile}
        $sudoString rm -f ${destFile}.tmp
    else
        mv ${destFile}.tmp ${destFile}
    fi
    
    return 0
}

fetch_file_from_ena_over_http() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}

    check_variables "enaFile" "destFile"

    # Convert
    local enaPath=$(convert_ena_fastq_to_uri $enaFile http $library)
    
    # Fetch
    fetch_file_by_wget $enaPath $destFile $retries http ena
}

fetch_file_from_ena_over_ftp() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}

    check_variables "enaFile" "destFile"
    
    # Convert
    local enaPath=$(convert_ena_fastq_to_uri $enaFile ftp $library)

    # Fetch
    fetch_file_by_wget $enaPath $destFile $retries ftp ena
}

# Convert an SRA-style file to its path on the ENA node 

convert_ena_fastq_to_ssh_path(){
    local fastq=$1
    local status=${2:-'public'}
    local library=${3:-''}

    local fastq=$(basename $fastq)
    if [ "$status" == 'private' ]; then
        if [ "$library" == '' ]; then
            echo "For private FASTQ files, the library cannot be inferred from the file name and must be specified" 1>&2
            return 1
        fi 
    else
        library=$(echo $fastq | grep -o "[SED]RR[0-9]*")
    fi

    local libDir=
    if [ "$status" == 'private' ]; then
        libDir=$(dirname $(get_library_path $library $ENA_PRIVATE_SSH_ROOT_DIR 'short'))
    else
        libDir=$(dirname $(get_library_path $library $ENA_SSH_ROOT_DIR))
    fi

    echo $libDir/$fastq
}

# Convert an SRA-style file to its URI 

convert_ena_fastq_to_uri() {
    local fastq=$1
    local uriType=${2}
    local library=${3:-''}

    local fastq=$(basename $fastq)

    if [ "$library" == '' ]; then
         library=$(echo $fastq | grep -o "[SED]RR[0-9]*")
    fi

    local libDir=$(dirname $(get_library_path $library))

    if [ "$uriType" == 'http' ]; then
        echo ${ENA_HTTP_ROOT_PATH}/$libDir/$fastq
    else
        echo ${ENA_FTP_ROOT_PATH}/$libDir/$fastq
    fi
}

# Check a URI is valid

function validate_url(){

    wget -q -S --spider $1 > /dev/null 2>&1
    response=$?

    if [ $? -ne 0 ]; then
        echo "URI $1 is invalid" 1>&2
        return $response
    else 
        echo "Link $1 valid"
    fi
}
