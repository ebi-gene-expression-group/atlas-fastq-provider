#!/usr/bin/env bats

# Extract the test data
setup() {
    test_dir="post_install_tests"
    data_dir="${test_dir}/data"
    output_dir="${test_dir}/outputs"
    fastq="ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR188/002/ERR1888172/ERR1888172_1.fastq.gz"
    fastq_file_ftp="${output_dir}/ERR1888172_1.ftp.fastq.gz"
    fastq_file_http="${output_dir}/ERR1888172_1.http.fastq.gz"
    sra="sra/ftp://ftp.sra.ebi.ac.uk/vol1/srr/SRR100/060/SRR10069860/SRR10069860_1.fastq.gz"
    sra_lib="SRR10069860"
    sra_file_ftp="${output_dir}/SRR10069860_1.sra.ftp.fastq.gz"
    sra_file_http="${output_dir}/SRR10069860_1.sra.http.fastq.gz"
    sra_file_lib_ftp="${output_dir}/SRR10069860_1.fastq.gz"
    export NOPROBE=1    

    if [ ! -d "$data_dir" ]; then
        mkdir -p $data_dir
    fi

    if [ ! -d "$output_dir" ]; then
        mkdir -p $output_dir
    fi
}

@test "Download Fastq file from FTP" {
    if  [ "$resume" = 'true' ] && [ -f "$fastq_file_ftp" ]; then
        skip "$fastq_file_ftp exists"
    fi

    run rm -rf $fastq_file_ftp && eval "./fetchFastq.sh -f $fastq -m ftp -t $fastq_file_ftp"

    [ "$status" -eq 0 ]
    [ -f "$fastq_file_ftp" ]
}

@test "Download and unpack SRA file from FTP, providing prefixed link" {
    if  [ "$resume" = 'true' ] && [ -f "$sra_file_ftp" ]; then
        skip "$sra_file_ftp exists"
    fi

    run rm -rf $sra_file_ftp && eval "./fetchFastq.sh -f $sra -m ftp -t $sra_file_ftp"

    [ "$status" -eq 0 ]
    [ -f "$sra_file_ftp" ]
}

@test "Download and unpack SRA file from FTP, providing just a library identifier" {
    if  [ "$resume" = 'true' ] && [ -f "$sra_file_lib_ftp" ]; then
        skip "$sra_file_lib_ftp exists"
    fi

    run rm -rf $sra_file_lib_ftp && eval "fetchEnaLibraryFastqs.sh -l ${sra_lib} -d ${output_dir} -m ftp -t srr"

    [ "$status" -eq 0 ]
    [ -f "$sra_file_lib_ftp" ]
}

#@test "Download Fastq file from HTTP" {
#    if  [ "$resume" = 'true' ] && [ -f "$fastq_file_http" ]; then
#        skip "$fastq_file_http exists"
#    fi

#    run rm -rf $fastq_file_http && eval "./fetchFastq.sh -f $fastq -m http -t $fastq_file_http"

#    [ "$status" -eq 0 ]
#    [ -f "$fastq_file_http" ]
#}


#@test "Download and unpack SRA file from HTTP" {
#    if  [ "$resume" = 'true' ] && [ -f "$sra_file_http" ]; then
#        skip "$sra_file_http exists"
#    fi

#    run rm -rf $sra_file_http && eval "./fetchFastq.sh -f $sra -m http -t $sra_file_http"

#    [ "$status" -eq 0 ]
#    [ -f "$sra_file_http" ]
#}
