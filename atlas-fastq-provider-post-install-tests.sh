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
    non_ena_sra="sra/https://sra-download.ncbi.nlm.nih.gov/traces/sra43/SRR/010931/SRR11194113/SRR11194113_3.fastq.gz"
    non_ena_sra_file="${output_dir}/SRR11194113_3.fastq.gz"
    export NOPROBE=1

    ena_lib_se="SRR18315788"
    fastq_file_ftp_se="${output_dir}/SRR18315788.fastq.gz"
    fastq_file_ftp_se_1="${output_dir}/SRR18315788_1.fastq.gz"
    fastq_file_ftp_se_2="${output_dir}/SRR18315788_2.fastq.gz"
    ena_lib_pe="SRR15832741"
    fastq_file_ftp_pe_1="${output_dir}/SRR15832741_1.fastq.gz"
    fastq_file_ftp_pe_2="${output_dir}/SRR15832741_2.fastq.gz"

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

#@test "Download and unpack non-ENA SRA file from FTP, providing prefixed link" {
#    if  [ "$resume" = 'true' ] && [ -f "$non_ena_sra_file" ]; then
#        skip "$non_ena_sra_file exists"
#    fi
#
#    run rm -rf $non_ena_sra_file && eval "./fetchFastq.sh -f $non_ena_sra -m ftp -t $non_ena_sra_file"
#
#    [ "$status" -eq 0 ]
#    [ -f "$non_ena_sra_file" ]
#}

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

@test "Download and unpack SRA file as SE, providing just a SE library identifier (no deinterleave attempt)" {
    if  [ "$resume" = 'true' ] && [ -f "$fastq_file_ftp_se" ]; then
        skip "$fastq_file_ftp_se exists"
    fi

    run rm -rf $fastq_file_ftp_se && eval "fetchEnaLibraryFastqs.sh -l ${ena_lib_se} -d ${output_dir}  -m ftp -t fastq -n SINGLE"

    [ "$status" -eq 0 ]
    [ -f "$fastq_file_ftp_se" ]
}

@test "Download and unpack SRA file as PE, providing just a SE library identifier (failed deinterleave attempt)" {
    if  [ "$resume" = 'true' ] && [ -f "$fastq_file_ftp_se_1" ] && [ -f "$fastq_file_ftp_se_2" ]; then
        skip "$fastq_file_ftp_se_1 and $fastq_file_ftp_se_2 exist"
    fi

    run rm -rf $fastq_file_ftp_se_1 && run rm -rf $fastq_file_ftp_se_2 && run fetchEnaLibraryFastqs.sh -l ${ena_lib_se} -d ${output_dir} -m ftp -t fastq -n PAIRED

    [ "$status" -eq 1 ]
    [  ! -f "$fastq_file_ftp_se_1" ]
    [  ! -f "$fastq_file_ftp_se_2" ]
}

@test "Download and unpack SRA file as PE, providing just a PE library identifier" {
    if  [ "$resume" = 'true' ] && [ -f "$fastq_file_ftp_pe_1" ] && [ -f "$fastq_file_ftp_pe_2" ]; then
        skip "$fastq_file_ftp_pe_1 and $fastq_file_ftp_pe_2 exist"
    fi

    run rm -rf $fastq_file_ftp_pe_1 && run rm -rf $fastq_file_ftp_pe_2 && run fetchEnaLibraryFastqs.sh -l ${ena_lib_pe} -d ${output_dir} -m ftp -t fastq -n PAIRED

    [ "$status" -eq 0 ]
    [  -f "$fastq_file_ftp_pe_1" ]
    [  -f "$fastq_file_ftp_pe_2" ]
}
