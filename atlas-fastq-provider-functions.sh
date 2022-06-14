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

            # ENA pattern is:
            # 
            # - 6-digit codes under e.g. SRR123456
            # - 7-digit codes under e.g. 007/SRR1234567
            # - 8-digit codes under e.g. 078/SRR12345678
            #
            # i.e. we zero-pad to three digits anything after and including the
            # 10th digit. Where we have e.g. '09' we need to strip leading
            # zeros to prevent octal errors with bash.

            digits=$(echo ${library:9} | sed 's/^0*//');
            prefix="$(printf %03d $digits)/"
        fi
    fi
    echo "${rootDir}/${subDir}/${prefix}${library}/${library}"
}

# Derive a library ID from a URI

get_library_id_from_uri() {
    local uri=$1
    local library=
    library=$(echo $uri | grep -Eo "[SED]RR[0-9]{5,9}" | head -n 1)
    if [ $? -ne 0 ]; then
        echo "No ENA/SRA ID found in $uri" 1>&2
        return 1
    else 
        echo -n "$library"
    fi
}

# Check a list of variables are set

check_variables() {
    vars=("$@")

    for variable in "${vars[@]}"; do
        local value=${!variable}        
        #if [[ -z ${!variable+x} ]]; then   # indirect expansion here
        if [ -z $value ]; then
            echo "ERROR: $variable not set" 1>&2
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
        echo "ERROR: To query or download files from the ENA server using ssh you need to set the environment variable ENA_SSH_USER. This is a user to which you can sudo, and which can SSH to $ENA_SSH_HOST and retrieve files from $ENA_SSH_ROOT_DIR." 1>&2
        return 1
    else
        return 0
    fi
}

# Get a string to sudo as necessary

fetch_ena_sudo_string() {

    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 6
    fi 
    
    # Check if we need to sudo, and if we can

    currentUser=$(whoami)
    if [ $currentUser != "$ENA_SSH_USER" ]; then
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

validate_ena_ssh_path() {
    local enaFile=$1

    local sudoString=
    sudoString=$(fetch_ena_sudo_string)
    if [ $? -ne 0 ]; then 
        return 1; 
    fi
    
    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 1
    fi 

    $sudoString ssh -n ${ENA_SSH_HOST} "ls ${enaFile}" > /dev/null 2>&1 
    if [ $? -eq 0 ]; then
        return 0
    else
        echo "ERROR: ${enaFile} not present on ${ENA_SSH_HOST}" 1>&2
        return 1
    fi
}

# Link local file

link_local_file() {
    
    local sourceDir=$1
    local sourceFile=$2
    local destFile=$3
        
    check_variables 'sourceDir' 'sourceFile' 'destFile'
   
    # Check source directory exists
 
    if [ ! -d "$sourceDir" ]; then
        echo "$sourceDir is not a directory" 1>&2
        return 7   
    fi

    # Convert relative to absolute

    if [ "${sourceDir:0:1}" != "/" ]; then
        sourceDir=$(pwd)/$sourceDir
    fi
    
    # Check file itself exists
    
    if [ -e "$destFile" ]; then
        return 2

    elif [ -e "$sourceDir/$sourceFile" ]; then
        ln -s $sourceDir/$sourceFile $destFile
    
    else
        echo "ERROR: Local file $sourceFile does not exist" 1>&2
        return 5
    fi
}

# Link files from a local directory to a targe directory

link_local_dir() {
    
    local sourceDir=$1
    local destDir=$2
    local library=${3:-''}

    # Check source directory exists
 
    if [ ! -d "$sourceDir" ]; then
        echo "$sourceDir is not a directory" 1>&2
        return 7   
    fi

    # Convert relative to absolute
     
    mkdir -p $destDir
    local dirFiles=$(ls $sourceDir)

    # If library is specified, only link files maching the pattern

    if [ -n "$library" ]; then
        dirFiles=$(echo -e "$dirFiles" | grep $library)
        if [ $? -ne 0 ]; then
            echo "No files matching $library in source directory $sourceDir" 1>&2
            return 8
        fi
    fi

    # If library is specified, only link files maching the pattern

    if [ -n "$library" ]; then
        dirFiles=$(echo -e "$dirFiles" | grep $library)
    fi

    # Do the linking

    if [ -n "$dirFiles" ]; then
        echo -e "$dirFiles" | while read -r l; do
            link_local_file $sourceDir $l $destDir/$l
        done
    fi
}

# Get the current temp dir

get_temp_dir() {
    
    local tempdir=
    
    if [ -n "$FASTQ_PROVIDER_TEMPDIR" ]; then
        tempdir="$FASTQ_PROVIDER_TEMPDIR"
    else
        if [ -n "$TMPDIR" ]; then
            tempdir="${TMPDIR}/atlas-fastq-provider"
        else
            tempdir=$(pwd)/tmp/atlas-fastq-provider
        fi
        export FASTQ_PROVIDER_TEMPDIR=$tempdir
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
        echo "ERROR: Invalid unit '$units'" 1>&2
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
        touch $testfile
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
    local fetchFreqMillis=${FETCH_FREQ_MILLIS:-500}

    check_variables 'action'
    
    local last_time=
    last_time=$(time_since_last $action)
    while [ $? -ne 0 ] || (( $(echo "$last_time < $fetchFreqMillis" |bc -l) )); do
        # Sleep for 1/100th of a second
        sleep 0.01 

        # Check last_time again- other processes could have altered it
        last_time=$(time_since_last $action)
    done
    record_action $action
}

# Verify a .gz file

verify_gz(){
    local gzfile=$1

    local gzstat=0

    echo "... Verifying $gzfile integrity"
    gzip_status=0
    gzip -t $gzfile > /dev/null
    gzip_status=$?
    if [ $gzip_status -ne 0 ]; then
        echo "... $gzfile file seems corrupt/ truncated"
        gzstat=1 
    else
        echo "... $gzfile looks good"
    fi
    return $gzstat
}

# Fetch a URI by wget

fetch_file_by_wget() {
    local sourceFile=$1
    local destFile=$2
    local retries=${3:-3}
    local method=${4:-''}
    local source=${5:-''}
    local validateOnly=${6:-''}

    check_variables "sourceFile" "destFile"
    
    # Check that the URI is valid

    validate_url $sourceFile
    if [ $? -ne 0 ]; then
        return 5
    elif [ -n "$validateOnly" ]; then
        return 0
    fi
    
    # Check destination file not already present

    if [ -e "$destFile" ]; then
        return 2
    fi

    # If the source is $ENA, check the method is currently working 
    
    if [ "$source" == 'ena' ]; then
        check_ena_method $method
        if [ $? -ne 0 ]; then
            return 3
        fi
    fi

    # All being well proceed with the download

    mkdir -p $(dirname $destFile)
    local wgetTempFile=${destFile}.tmp
    local fetch_status=1
    
    for i in $(seq 1 $retries); do 
        echo "Downloading $sourceFile to $(realpath $destFile) using wget"
        
        rm -f $wgetTempFile
        if [ "$method" != '' ]; then
            wait_and_record ${source}_$method
        fi
        response=$(wget  -nv -c $sourceFile -O $wgetTempFile 2>&1) 
        fetch_status=$?
        
        if [ "$fetch_status" -ne 0 ]; then
            echo "... wget failed (error was: $response)" 1>&2
        else 
            echo "$sourceFile" | grep '\.gz$' > /dev/null   
            if [ $? -eq 0 ]; then
                verify_gz $wgetTempFile
                fetch_status=$?
            fi
        fi
        if [ "$fetch_status" -eq "0" ]; then
            break
        elif [ "$i" -lt "$retries" ]; then
            echo "... Retrying..."
            sleep 1
        else
            echo "Unable to fetch $sourceFile after $retries retries"
        fi
        rm -f $wgetTempFile
    done
 
    if [ $fetch_status -ne 0 ] || [ ! -s $wgetTempFile ] ; then
        echo "ERROR: Failed to retrieve $sourceFile to ${destFile}" 1>&2
        rm -f $wgetTempFile 
        return 1
    else
        echo "$wgetTempFile success!" 1>&2
        mv $wgetTempFile $destFile
    fi
}

# Fetch file using the HCA client

function fetch_file_by_hca {
    local sourceFile=$1
    local destFile=$2

    local exitcode=8

    sourceFile="${sourceFile#hca://}"
    sourceFile="${sourceFile#hca/}"
    local sourceFileName=$(basename $sourceFile)
    local bundle=$(echo $sourceFile | awk -F'/' '{print $1}')
    
    local bundleUriTemplate=${DCP_BUNDLE_URI:-'https://service.azul.data.humancellatlas.org/index/bundles/BUNDLE'}
    local bundleCatalogs=${DCP_BUNDLE_CATALOGS:-'dcp1 dcp7'}
    local bundleUri=$(echo $bundleUriTemplate | sed "s/BUNDLE/$bundle/g")

    # Check multiple catalogs for this bundle UUID

    for catalog in ${bundleCatalogs}; do
        json_response=$(curl -X GET "${bundleUri}?catalog=$catalog" -H "accept: application/json")
        if [ $(echo "$json_response"| jq  -e 'has("files")') != 'true' ]; then
            echo "Failed to find files for bundle $bundle in ${catalog}, response was $json_response" 1>&1
        else
            bundle_content=$(echo "$json_response" | jq '.files[] | select(.name=="'$sourceFileName'")')
            if [ $? -ne 0 ]; then
                echo "Can't get bundle content for UUID $bundle" 1>&2
            else
                url=$(echo "$bundle_content" | jq -r '.url')
                sha256=$(echo "$bundle_content" | jq -r '.sha256')

                wget -O $destFile $url
                if [ $? -ne 0 ]; then
                    echo "wget for $sourceFileName in $bundle using URL $url failed" 1>&2
                else
                    file_md5sum=$(md5sum $destFile | awk '{print $1}')
                    if [ "$file_md5sum" != "$sha256" ]; then
                        echo "File checksums for $sourceFileName in bundle $bundle good"
                        exitCode=0
                        break
                    else
                        echo "File checksums for $sourceFileName in bundle $bundle bad" 1>&2
                    fi
                fi

                # We found right catalog even if the file was corrupted etc, so
                # break here regardless
                break
            fi
        fi    
    done

    return $exitCode
}

# Get all the files from an SRA file for a library

function fetch_library_files_from_sra_file() {
    local sraFile=$1
    local outputDir=${2:-"$(pwd)"}
    local retries=${3:-3}
    local method=${4:-'auto'}
    local status=${5:-'public'}
    local tempdir=$(get_temp_dir)
    local returnCode=0

    check_variables 'sraFile' 'outputDir'

    local library
    library=$(get_library_id_from_uri $sraFile)

    local sourceFile=$(dirname $(get_library_path $library $ENA_FTP_ROOT_PATH/srr))
    outputDir=$(realpath $outputDir)

    # If user has specifified wget, reset to FTP for ENA

    if [ "$method" = 'wget' ]; then
        method=ftp
    fi

    echo "Downloading file $sourceFile"
    if [ $method == 'auto' ]; then
        fetchMethod='fetch_file_from_ena_auto'
    else
        fetchMethod="fetch_file_from_ena_over_$method"
    fi

    mkdir -p $tempdir/$library
    
    pushd $tempdir/$library > /dev/null

    if [ ! -e $library ]; then
        $fetchMethod $library $library $retries "" "" "srr" $status
        returnCode=$?
        
        # Fall back to a simple wget in case the SRA file is not in ENA

        if [ $returnCode -ne 0 ]; then
            echo "Failed to get SRA file $sraFile from ENA, now trying a simple wget" 1>&2
            fetch_file_by_wget $sraFile $library
            returnCode=$?
        fi
    fi

    if [ $returnCode -eq 0 ]; then
        if [ -e "$library" ]; then
            hash fastq-dump 2>/dev/null || { echo >&2 "The NCBI fastq-dump tool is required,  but it's not installed.  Aborting."; exit 1; }
            fastq-dump -I --split-files --gzip $library
            if [ $? -eq 0 ]; then
                nlines=
                lastfile=
                while read -r l; do
                    filelines=$(zcat $l | wc -l)                   
                    if [ -n "$nlines" ] && [ "$nlines" -ne "$filelines" ]; then
                        echo "Line number mismatch ($filelines in $l vs $nlines in $lastfile)- download and unpacking has likely not happened correctly" 1>&2
                        returnCode=9
                        break
                    else
                        nlines=$filelines
                        lastfile=$l
                    fi
                done <<< "$(ls *.fastq.gz)"

                mv *.fastq.gz $outputDir
            else
                returnCode=9
            fi
        else
            echo "$library was not retrieved using $sourceFile" 1>&2
            returnCode=9
        fi
    fi
    popd > /dev/null

    if [ $returnCode -eq 0 ]; then
        rm -rf $tempdir/$library
    fi

    return $returnCode
}

# Fetch file from an SRA file. Try to put all output files in the same location
# as the main target to prevent multiple calls for the same SRA package.
# Expect URIs like
# sra/ftp://ftp.sra.ebi.ac.uk/vol1/srr/SRR100/061/SRR10009461/SRR10009461_2.fastq
# This will pull ftp://ftp.sra.ebi.ac.uk/vol1/srr/SRR100/061/SRR10009461 (.sra
# file) and extract SRR10009461_2.fastq

function fetch_file_by_sra {
    local sourceFile=$1
    local destFile=$2
    local retries=${3:-3}
    local method=${4:-'auto'}
    local status=${5:-'public'}
    local returnCode=0

    sourceFile=$(echo "$sourceFile" | sed 's/^sra\///')
    destFile=$(realpath $destFile)
    destDir=$(dirname $destFile)

    local sraUri=$(dirname $sourceFile)
    local sraFile=$(echo -e "$sourceFile"| awk -F "/" '{print $NF}')

    if [ $returnCode -eq 0 ]; then
        fetch_library_files_from_sra_file "$sraUri" "$destDir" "$retries" "$method" "$status" 
        returnCode=$?
        
        if [ $returnCode -eq 0 ]; then

            # If user has specified a different destination path, rename   
         
            if [ ! -e $destDir/$sraFile ]; then
                echo "$sraFile was not retrieved using $sraName" 1>&2
                returnCode=9
            else
                if [ "$destDir/$sraFile" != "$destFile" ]; then
                    mv "$destDir/$sraFile" "$destFile"
                fi
            fi
        fi
    fi

    return $returnCode
}

# Run a command/function in a time-limited fashion

function run_timed_cmd { 
    local cmd=$1 
    local timeout=$2
   
    echo "Running: \"$cmd\", timing out after $timeout seconds"
 
    $cmd &
    local pid=$!

    # Test for immediate failure, then wait the timeout

    local slept=0

    for sleep in $(seq 1 $timeout); do
        sleep 1
        
        kill -0 "$pid" > /dev/null 2>&1

        # Process still running - kill it at the timeout

        if [ $? -eq 0 ]; then
            if [ "$slept" -eq "$timeout" ]; then

                # For some reason the below doesn't always work, so kill child
                # processes explicitly first

                pgrep -P $pid | while read -r l; do
                    echo "Killing $l"
                    kill -9 $l
                    echo "Waiting until $l dies... "
                    wait $l
                done

                echo "Killing $pid"
                kill -9 $pid
                return 42
            fi

        # Process not still running - use wait to collect its exit code

        else 
            wait $pid
            return $?
        fi  

    done
}

# Probe available ENA download methods and determine response times

probe_ena_methods() {

    local probe_file=${1:-''}
    local tempdir=$(get_temp_dir)
    local allowedDownloadMethods=${ALLOWED_DOWNLOAD_METHODS:-'ftp http ssh'}
    local testFile=   
 
    if [ -z "$probe_file" ]; then
        probe_file=$tempdir/fastq_provider.probe
    fi

    echo -e "method\tresult\tstatus\telapsed_time\tdownload_speed" > ${probe_file}.tmp

    export NOPROBE=1

    # If all methods results in NA (not working), try a couple of times more
    # before giving up

    local have_working_method=0
   
    for try in 1 2 3; do
        for method in $allowedDownloadMethods; do
            echo "Testing method $method for ${try}th time..." 1>&2

            local testOutput=$tempdir/${method}_test.fq.gz
            rm -f $testOutput ${testOutput}.tmp 

            local function="fetch_file_from_ena_over_$method"
            local start_time=$SECONDS
            run_timed_cmd "$function $ENA_TEST_FILE $testOutput 1" 30 > /dev/null 2>&1 
            local status=$?
            local elapsed_time=$(($SECONDS - $start_time))
                    
            # A timeout means it was probably downloading, if slowly
            
            local result=success
            local download_speed=NA
        
            if [ "$status" -eq 42 ]; then
                echo "WARNING: Killed download process, taking too long" 1>&2
                if [ -e ${testOutput}.tmp ]; then
                    mv ${testOutput}.tmp $testOutput
                else
                    result=failure
                fi
            elif [ "$status" -ne 0 ]; then
                echo "Failed (status $status)" 1>&2
                result=failure
            else
                echo "Success: $method is working" 1>&2
                have_working_method=1
            fi

            if [ "$result" == 'success' ]; then
                local test_file_size=$(stat --printf="%s" $testOutput)
                download_speed=$(bc -l <<< "scale=2; $test_file_size / 1000000 / $elapsed_time")
            fi
            echo -e "$method\t$result\t$status\t$elapsed_time\t$download_speed" >> ${probe_file}.tmp
            rm -f $testOutput
        done

        if [ $have_working_method -eq 1 ]; then
            break
        fi 
    done   

    export NOPROBE=
    mv ${probe_file}.tmp ${probe_file}
    echo "ENA retrieval probe results at ${probe_file}" 1>&2
}

# Update the probe if it's got too old

update_ena_probe() {

    local tempdir=$(get_temp_dir)
    local probeUpdateFreqMins=${PROBE_UPDATE_FREQ_MINS:-15}
    local probe_file=$tempdir/fastq_provider.probe

    if [ ! -e $probe_file ]; then
        echo "Creating ENA probe file, testing available download methods" 1>&2
        probe_ena_methods
        echo "Done with probe" 1>&2
    fi
    local probe_age=$(file_age $probe_file mins)
    if (( $(echo "$probe_age > $probeUpdateFreqMins" |bc -l) )); then
        echo "Probe file is older than $probeUpdateFreqMins mins (at $probe_age mins), updating" 1>&2
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

    if [ -z "$NOPROBE" ]; then
        update_ena_probe
    else
        return 0
    fi

    if [ -e "$probe_file" ]; then
        local method_status=$(tail -n +2 $probe_file | awk '$1=="'$method'"' | awk '{print $5}')
        if [ "$method_status" == 'NA' ]; then
            return 1
        else
            return 0
        fi
    else
        return 0
    fi
}

# Select an ENA download method based on probed response time

select_ena_download_method() {
    
    local tempdir=$(get_temp_dir)
    local probe_file=$tempdir/fastq_provider.probe
    echo "probe file: $probe_file" 1>&2
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
            for met in $ALLOWED_DOWNLOAD_METHODS; do
                if [ "$met" == "$method" ]; then
                    ordered_methods="$ordered_methods $method"
                fi
            done
        fi
    done <<< "$(tail -n +2 $probe_file | awk '$5!="NA"' | sort -k 5,5rn)"
    
    if [ "$ordered_methods" == 'None' ] || [ "$ordered_methods" == '' ]; then
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
    local validateOnly=${5:-''}
    local downloadType=${6:-'fastq'}

    check_variables "enaFile" "destFile"
    
    # Check destination file not already present

    if [ -e "$destFile" ]; then
        return 2
    fi

    local methods=
    methods=$(select_ena_download_method)

    if [ $? -ne 0 ]; then
        echo "ERROR: No ENA download methods available" 1>&2
        return 3
    fi

    local exitCode=
    for i in $(seq 1 $retries); do 
        for method in $methods; do
            echo "Fetching $enaFile using method $method, attempt $i"
            function="fetch_file_from_ena_over_$method"
            $function $enaFile $destFile 1 "$library" "$validateOnly" "$downloadType"
            
            exitCode=$?
            if [ $exitCode -eq 0 ]; then 
                break 2
            else 
                echo "WARNING: Failed to retrieve $enaFile using method $method, attempt $i" 1>&2
            fi
        done    
    done

    return $exitCode
}

# Fetch a file from the ENA to a location

fetch_file_from_ena_over_ssh() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}
    local validateOnly=${5:-''}
    local downloadType=${6:-'fastq'}
    local status=${7:-'public'}
    local tempdir=$(get_temp_dir)

    check_variables "enaFile" "destFile"

    check_ena_ssh

    if [ $? -eq 1 ]; then
        return 6
    fi 
    
    check_ena_method 'ssh'
    if [ $? -ne 0 ]; then
        return 3
    fi

    # Check we can sudo to the necessary user
    local sudoString=
    sudoString=$(fetch_ena_sudo_string)
    if [ $? -ne 0 ]; then 
        return 4 
    fi

    # Convert to an ENA path
    enaPath=$(convert_ena_fastq_to_ssh_path $enaFile $status $library)

    # Check file is present at specified location    
    validate_ena_ssh_path $enaPath    
    if [ $? -ne 0 ]; then 
        return 5 
    elif [ -n "$validateOnly" ]; then
        return 0
    fi
    
    # Check destination file not already present

    if [ -e "$destFile" ]; then
        return 2
    fi
    
    # Make destination group-writable if we need to sudo
    
    local sshTempFile=${destFile}.tmp

    if [ "$sudoString" != '' ]; then
        local sshTempDir=$tempdir/ssh
        mkdir -p $sshTempDir
        chmod a+rwx $sshTempDir
        sshTempFile=$sshTempDir/$(basename ${destFile}).tmp
    fi
    
    rm -f $sshTempFile

    echo "Downloading remote file $enaPath to $destFile over SSH"
    
    # Run the rsync over SSH, sudo'ing if necessary use wait_and_record() to
    # avoid overloading the server

    mkdir -p $(dirname $destFile)
    local process_status=1
    for i in $(seq 1 $retries); do 
        
        wait_and_record 'ena_ssh'
    
        $sudoString rsync -ssh --inplace -avc ${ENA_SSH_HOST}:$enaPath $sshTempFile > /dev/null
        if [ $? -eq 0 ]; then
            process_status=0
            break
        fi
    done    

    if [ $process_status -ne 0 ] || [ ! -s ${sshTempFile} ] ; then
        echo "ERROR: Failed to retrieve $enaPath to ${destFile}" 1>&2
        return 1
    fi

    # Move or copy files to final locations

    if [ "$sudoString" != '' ]; then
        $sudoString chmod a+r ${sshTempFile}
        cp ${sshTempFile} ${destFile}
        $sudoString rm -f ${sshTempFile}
    else
        mv ${sshTempFile} ${destFile}
    fi
    
    return 0
}

fetch_file_from_ena_over_http() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}
    local validateOnly=${5:-''}
    local downloadType=${6:-'fastq'}

    check_variables "enaFile" "destFile"

    # Convert
    local enaPath=$(convert_ena_fastq_to_uri $enaFile http "$library" "$downloadType")
    
    # Fetch
    fetch_file_by_wget $enaPath $destFile $retries http ena $validateOnly
}

fetch_file_from_ena_over_ftp() {
    local enaFile=$1
    local destFile=$2
    local retries=${3:-3}
    local library=${4:-''}
    local validateOnly=${5:-''}
    local downloadType=${6:-'fastq'}

    check_variables "enaFile" "destFile"
 
    # Convert
    local enaPath=$(convert_ena_fastq_to_uri $enaFile ftp "$library" "$downloadType")

    # Fetch
    fetch_file_by_wget $enaPath $destFile $retries ftp ena $validateOnly
}

# Convert an SRA-style file to its path on the ENA node 

convert_ena_fastq_to_ssh_path(){
    local fastq=$1
    local status=${2:-'public'}
    local library=${3:-''}
    local returnCode=0

    local fastq=$(basename $fastq)
    if [ "$status" == 'private' ]; then
        if [ "$library" == '' ]; then
            echo "ERROR: For private FASTQ files, the library cannot be inferred from the file name and must be specified" 1>&2
            returnCode=1
        fi 
    else
        library=$(get_library_id_from_uri $fastq)
        returnCode=$?
    fi

    if [ $returnCode -ne 0 ]; then
        return $returnCode
    else
        local libDir=
        if [ "$status" == 'private' ]; then
            libDir=$(dirname $(get_library_path $library $ENA_PRIVATE_SSH_ROOT_DIR 'short'))
        else
            libDir=$(dirname $(get_library_path $library $ENA_SSH_ROOT_DIR/fastq))
        fi

        echo $libDir/$fastq
    fi
}

# Convert an SRA-style file to its URI 

convert_ena_fastq_to_uri() {
    local fastq=$1
    local uriType=${2}
    local library=${3:-''}
    local downloadType=${4:-'fastq'}
    local returnCode=0

    # .sra file downloads are just like
    # https://hx.fire.sdo.ebi.ac.uk/fire/public/sra/srr/SRR100/061/SRR10009461
    # (so just looks like the dir if this was for an FTP file)
    if [ "$library" == '' ]; then
        library=$(get_library_id_from_uri $fastq)
        returnCode=$?
    fi
    
    if [ $returnCode -eq 0 ]; then
        if [ "$downloadType" = 'fastq' ]; then
            fastq="/$(basename $fastq)"
        else
            fastq=''
        fi

        local libDir=$(dirname $(get_library_path $library))
        if [ "$uriType" == 'http' ]; then
            echo ${ENA_HTTP_ROOT_PATH}/$downloadType/$libDir$fastq
        else
            echo ${ENA_FTP_ROOT_PATH}/$downloadType/$libDir$fastq
        fi
    fi
}

# Check a URI is valid

validate_url(){

    local response=

    response=$(wget -S --spider $1 2>&1)
    local returnCode=$?

    echo $response | grep -i "no such file" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "ERROR: URI $1 is invalid" 1>&2
        return $returnCode
    else
        echo $response | grep -i "exists" > /dev/null 2>&1
        echo "URI $1 is valid"
    fi
}

# Get all files for a given library

get_library_listing() {
    local library=$1
    local method=${2:-'ssh'}    
    local status=${3:-'public'}
    local tempdir=$(get_temp_dir)

    check_variables 'library'

    local libDir=
    if [ "$method" == 'ssh' ]; then
        if [ "$status" == 'private' ]; then
            libDir=$(dirname $(get_library_path $library $ENA_PRIVATE_SSH_ROOT_DIR 'short'))
        else
            libDir=$(dirname $(get_library_path $library $ENA_SSH_ROOT_DIR/fastq))
        fi
    else
        libDir=$(dirname $(get_library_path $library $ENA_FTP_ROOT_PATH/fastq))
    fi
    
    if [ "$method" == 'ssh' ]; then
        local sudoString=
        sudoString=$(fetch_ena_sudo_string)

        if [ $? -ne 0 ]; then 
            return 4 
        fi
        
        $sudoString ssh -n ${ENA_SSH_HOST} ls $libDir/*

    else
        
        # This must be done in a tempdir, since the listing file cannot be
        # anything other than '.listing', and we therefore get clashes with
        # multiple downloads at once         

        local listingDir="$tempdir/${library}_listing"
        mkdir -p $listingDir

        pushd $listingDir > /dev/null
        wget --spider --no-remove-listing $libDir/ > /dev/null 2>&1
        if [ ! -e .listing ]; then
            echo "ERROR: no files found at $libDir" 1>&2
            return 1
        fi

        cat .listing | grep -vP "\.\s+$" | awk '{print $NF}' | while read -r l; do
            echo $libDir/$l | sed 's/\r$//' 
        done
        popd > /dev/null
        
        rm -rf $listingDir
    fi
}

# Fetch all available files for a given library

fetch_library_files_from_ena() {
    local library=$1
    local outputDir=$2
    local retries=${3:-3}
    local method=${4:-'auto'}
    local status=${5:-'public'}
    local downloadType=${6:-'fastq'}
    local sepe=${7:-'PAIRED'}

    #mkdir -p ${outputDir}.tmp
    local tempdir=$(get_temp_dir)
    check_variables 'library'

    local filenames_array=()

    local listMethod='ftp'
    if [ "$method" == 'ssh' ]; then
        listMethod='ssh'
    fi

    local libraryListing=
    libraryListing=$(get_library_listing $library $listMethod $status)
    local exitCode=$?
    echo $libraryListing
    if [ $exitCode -ne 0 ]; then
        return 5
    else
        set +m # To disable job control
        echo -e "$libraryListing" | while read -r l; do
           shopt -s lastpipe
           local filenames_arr=()
           local fileName=$(basename $l )
            if [ "$sepe" == "PAIRED" ]; then
                echo $fileName
                if [[ "$fileName" =~ _[0-9]".fastq.gz" ]]; then  
                    filenames_arr+=( "${fileName//_*fastq.gz/}" )
                else
                    echo "WARNING: paired-end provided, but it could actually be single end"
                    filenames_arr+=( "${fileName//.fastq.gz/}" )
                fi
           else
              filenames_arr+=( "${fileName//.fastq.gz/}" )
           fi
           echo "Downloading file $fileName for $library to ${tempdir}"
            if [ $method == 'auto' ]; then
                fetchMethod='fetch_file_from_ena_auto'
            else
                fetchMethod="fetch_file_from_ena_over_$method"
            fi

            $fetchMethod $l ${tempdir}/$fileName $retries $library "" "$downloadType" $status
            local returnCode=$?
            if [ $returnCode -ne 0 ]; then
                return $returnCode
            fi
            echo $filenames_arr
            filenames_array=("${filenames_arr[@]}") 
        done 
        set -m

    fi

    # A sleep here to try to deal with cases where we get a success exit code
    # above, but the file does not exist when checked below. Suspect some sort of
    # file system latency, so maybe if we wait a bit before checking it will solve
    # the issue.

    sleep 10

    if [ "$sepe" == "PAIRED" ]; then

        # get base filenames to be checked
        echo "paired end"
        echo "${filenames_array[@]}" 
        uniq=($(printf "%s\n" "${filenames_array[@]}" | sort -u | tr '\n' ' ' ))
        echo "${uniq[@]}" 
        
        for basefile in "${uniq[@]}"; do
            
            localFastqPath=${tempdir}/$basefile 

            if [ ! -s "${localFastqPath}_1.fastq.gz" ] ||  [ ! -s "${localFastqPath}_2.fastq.gz" ]; then
    
                if [ -s "${localFastqPath}_1.fastq.gz" ]; then
        
                    # Only the _1 file exists, this is a possible interleaved situation                

                    mv ${localFastqPath}_1.fastq.gz ${localFastqPath}.fastq.gz
                fi

                # If we have a single file, see if we can deinterleave it

                if [ -s ${localFastqPath}.fastq.gz ]; then
                    echo "Trying to deinterleave a FASTQ file of paired reads into two FASTQ files"
                    gzip -dc ${localFastqPath}.fastq.gz | deinterleave_fastq.sh ${localFastqPath}_1.fastq ${localFastqPath}_2.fastq
                    # ${IRAP_SOURCE_DIR}/scripts/deinterleave.sh $possibleInterleavedFile ${localFastqPath} 2> /dev/null
            
                    if [ $? -ne 0 ]; then
                        rm -rf ${localFastqPath}*.fastq.gz
                        echo "ERROR: Failed to de-interleave ${localFastqPath}.fastq.gz"
                        exit 1
                    else
                        if [ ! -s "${localFastqPath}_1.fastq" ] ||  [ ! -s "${localFastqPath}_2.fastq" ]; then
                            rm -rf ${localFastqPath}*.fastq*
                            echo "ERROR: Failed to de-interleave, forward or reverse not generated"
                            exit 1
                        fi
                    fi
                    gzip ${localFastqPath}_*.fastq
                fi
                # Whether public or private, downloaded directly or created by
                # de-interleaving, we should now have both read files

                for readFile in ${localFastqPath}_1.fastq.gz ${localFastqPath}_2.fastq.gz; do
                    if [ ! -s $readFile ]; then
                        echo "ERROR: Failed to retrieve ${readFile}"
                        exit 1
                    fi
                done
            else
                echo "Read files already present"
            fi
        done

    else
        echo "single end"
        # get base filenames to be checked
        uniq=($(printf "%s\n" "${filenames_array[@]}" | sort -u | tr '\n' ' ' ))
        #printf "%s\n" "${uniq[@]}" 
        echo "${uniq[@]}" 
        
        for basefile in "${uniq[@]}"; do

            localFastqPath=${tempdir}/$basefile 

            if [ ! -s "${localFastqPath}.fastq.gz" ]; then
                # ENA has a bug: 'For some reason we dump
                # these runs differently as we expect a CONSENSUS to be dumped.  If
                # there is no CONSENSUS table found inside cSRA container we dump runs
                # as-is using --split-file option.' This results in single-end FASTQ
                # files being named <run_id>_1.fastq.gz. They say they will fix it, but
                # in the meantime, we need to use the following workaround.
        
                if [ -s ${localFastqPath}_1.fastq.gz ] && [ ! -s ${localFastqPath}_2.fastq.gz ]; then
                    mv ${localFastqPath}_1.fastq.gz ${localFastqPath}.fastq.gz
                fi
            fi

            if [ ! -s "${localFastqPath}.fastq.gz" ]; then
                echo "ERROR: ${localFastqPath}.fastq.gz not present: failed to retrieve $(basename ${localFastqPath}).fastq.gz"
                exit 1
            fi
        done
    fi


    cp -a ${tempdir}/. ${outputDir}/
    #rm -rf ${outputDir}.tmp
    echo "Retrieved $sepe-END $library from ENA successfully"

}

# Guess the origin of a file

guess_file_source() {
    local sourceFile=$1
    
    check_variables 'sourceFile'
 
    local fileSource='unknown'

    echo $sourceFile | grep -E "^(hca:|hca/)" > /dev/null
    if [ $? -eq 0 ]; then
        fileSource='hca'
    else
        echo $sourceFile | grep -E "(^sra/)" > /dev/null
        if [ $? -eq 0 ]; then
            fileSource='sra'
        else
            echo $(basename $sourceFile) | grep "[EDS]RR[0-9]*" > /dev/null
            if [ $? -eq 0 ]; then
                fileSource='ena'
            else
                echo "Cannot automatically determine source for $sourceFile" 1>&2
            fi
        fi
    fi
    
    echo $fileSource
}

