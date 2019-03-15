# Atlas FASTQ provider

Scripts and utilities for providing fastqs to workflows.

## Installation

This package can be installed via Bioconda:

```
conda install -c ebi-gene-expression-group atlas-fastq-provider
```

## Generic usage

```
fetchFastq.sh [-f <file or uri>] [-t <target file>] [-s <source resource or directory>] [-m <retrieval method>]
```

Only the source file (-f) and target (-t) arguments are compulsory. 

This is a generic utility to provide FASTQ files for use in pipelines etc. Files can be downloaded from links, or linked to files in directories on the file system. There are 'special cases' where things can be handled differently, for example in fetching files from ENA via SSH or the new HTTP endpoints. The special cases will be triggered based on the source, which if set to 'auto' (the default) will be guessed (e.g. ena for SRR/DRR/ERR identifiers). 

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

### Use a local diretory as a source, producing a symlink

```
fetchFastq.sh -f ERR1888646_1.fastq.gz -t ERR1888646_1.fastq.gz -s /path/to/dir
```
