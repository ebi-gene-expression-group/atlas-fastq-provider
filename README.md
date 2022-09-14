# Atlas FASTQ provider [![Anaconda-Server Badge](https://anaconda.org/ebi-gene-expression-group/atlas-fastq-provider/badges/installer/conda.svg)](https://anaconda.org/ebi-gene-expression-group/atlas-fastq-provider)

Scripts and utilities for providing fastqs to workflows.

## Installation

This package can be installed via Bioconda:

```
conda install -c ebi-gene-expression-group atlas-fastq-provider
```

## Configuration

Installation will create a file 'atlas-fastq-provider-config.sh' in the same install directory as the main script fetchFastq.sh. Config variables can be modified in this file.

```
ENA_SSH_HOST='sra-login-1'
ENA_SSH_ROOT_DIR='/nfs/era-pub/vol1/'
ENA_PRIVATE_SSH_ROOT_DIR='/private/path'
ENA_FTP_ROOT_PATH='ftp://ftp.sra.ebi.ac.uk/vol1'
ENA_HTTP_ROOT_PATH='https://hx.fire.sdo.ebi.ac.uk/fire/public/era'
FASTQ_PROVIDER_TEMPDIR='/tmp/atlas-fastq-provider'
ENA_TEST_FILE='ERR1888172_1.fastq.gz'
FETCH_FREQ_MILLIS=500
PROBE_UPDATE_FREQ_MINS=15
ENA_RETRIES=3
```

Overrides to these variables can also be supplied at runtime (see below).

## Usage

### Individual FASTQ files

```
fetchFastq.sh -f <file or uri> -t <target file> [-c <config file to override defaults>] [-s <source resource or directory>] [-m <retrieval method, default 'auto'>] [-p <public or private, default public>] [-l <library, by default inferred from file name>]
```

This is a generic utility to provide FASTQ files for use in pipelines etc. At the most basic level files can be downloaded from links, or linked to files in directories on the file system, with some extra sugar to indicate when a file is not present at the source and produce errors consistently etc.  

There are then 'special cases' where things can be handled differently, for example in fetching files from ENA via SSH or the new HTTP endpoint. The special cases will be triggered based on the source, which if set to 'auto' (the default) will be guessed (e.g. ena for SRR/DRR/ERR identifiers). 

For the ENA, there are three methods: FTP, SSH and HTTP. FTP is the default method that will work for everyone. EBI personal with the right privileges can also copy files over SSH directly from the ENA servers. There is also a new internal HTTP endpoint (currently unreliable) that can be used by EBI personnel. Specifying 'auto' will test each of these methods and select the fastest, storing results in a 'probe' file. This file will be updated according to the interval specified in the confi variable PROBE_UPDATE_FREQ_MINS.

### All files for an ENA library/ run:

```
fetchEnaLibraryFastqs.sh -l <library> -d <output directory> [-m <retrieval method, default 'auto'>] [-s <source directory for method 'dir'>] [-p <public or private, default public>] [-c <config file to override defaults>]
```

This is mostly a wrapper for fetchFastq.sh, following a listing of files at the source. 

### Validation only

Sometimes it's useful to check that a file exists at source, without actually downloading it. This can can be done by supplying '-v' to fetchFastq.sh, which will cause the script to return an exit code of 0 after the file existence is checked, but before download.

## Examples

### Download from ENA via FTP URI

```
fetchFastq.sh -f ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR188/006/ERR1888646/ERR1888646_1.fastq.gz -t ERR1888646_1.fastq.gz
```

### Download from ENA using new HTTP endpoint

```
fetchFastq.sh -f ERR1888646_1.fastq.gz -t ERR1888646_1.fastq.gz -m http
```

This fetches files using the new HTTP endpoint, as specified in ENA_HTTP_ROOT_PATH in the [config file](atlas-fastq-provider-config.sh).

### Download from ENA using SSH

```
fetchFastq.sh -f ERR1888646_1.fastq.gz -t ERR1888646_1.fastq.gz -m ssh
```

This will attempt to pull files directly from the ENA server, using the host and path in the [config file](atlas-fastq-provider-config.sh). To do this you must set environment variable 'ENA_SSH_USER'. This should be a user you either are, or can sudo to, with permissions to SSH to the SRA host. This is only likely to be possible if you're privileged member of staff at the EBI.

#### Private files

EBI personnel can also retrieve files from private locations on the ENA server by specifying ENA_PRIVATE_SSH_ROOT_DIR and running commands like:

```
fetchFastq.sh -f my_private_file1.fastq.gz -t my_private_file1.fastq.gz -p private -l ERR123456
```

Note that the library name must also be specified.

### Use a local diretory as a source, producing a symlink

```
fetchFastq.sh -f ERR1888646_1.fastq.gz -t ERR1888646_1.fastq.gz -s /path/to/dir
```

### Download all files from an ENA library

#### Fetching individual files

```
fetchEnaLibraryFastqs.sh -l ERR1888646 -d ERR1888646
```

#### Pulling and unpacking SRA files

```
fetchEnaLibraryFastqs.sh -l ERR1888646 -d ERR1888646 -t srr
```

### Download file from HCA

Files from the HCA can be downloaded given pseudo-URI formed like:

```
fetchFastq.sh -f hca://<bundle>/<file> -t <dest file>
```

... or by manually specifying method like:

```
fetchFastq.sh -m hca -f <bundle>/<file> -t <dest file>
```

This just passes the bundle UUID, along with the file filter, to [azul](https://service.azul.data.humancellatlas.org/#/Index/get_index_bundles__bundle_id_), which provides links to the fastq files, which can then be downloaded.

A real example is:

```
fetchFastq.sh -f hca://0359ab85-bb92-4e6e-a819-12aa734ed12b/10X127_1_S28_L001_I1_001.fastq.gz -t foo.fastq.gz
```
