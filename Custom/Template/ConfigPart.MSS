#### Agents related to mass storage operations

### AGENT LABEL=mss-remove PROGRAM=Toolkit/Transfer/FileRemove DEFAULT=off
 -db              ${PHEDEX_DBPARAM}
 -nodes           ${PHEDEX_MSS}
 -delete          ${PHEDEX_CONFIG}/FileDownloadDelete
 -protocol        'direct'

### AGENT LABEL=exp-pfn-mss PROGRAM=Toolkit/Transfer/FileExport
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_NODE},${PHEDEX_MSS}
 -accept      ${PHEDEX_NODE},${PHEDEX_MSS}
 -storagemap  ${PHEDEX_MAP}
 -protocols   'direct'

#### SRM based agents
### AGENT LABEL=mss-stage PROGRAM=Custom/SRM/FileSRMStager DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_NODE}
 -storagemap  ${PHEDEX_MAP}

### AGENT LABEL=mss-migrate PROGRAM=Toolkit/Transfer/FileMSSMigrate DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_MSS}
 -mssbackend  'srm'

#### Castor based agents
### AGENT LABEL=mss-stage PROGRAM=Custom/Castor/FileCastorStager DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_NODE}
 -storagemap  ${PHEDEX_MAP}

### AGENT LABEL=mss-migrate PROGRAM=Toolkit/Transfer/FileMSSMigrate DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_MSS}
 -mssbackend  'castor'

#### dCache based agents
#### Currently we don't have a native dCache stager,
#### hence a fake stager is used for now.
### AGENT LABEL=mss-stage PROGRAM=Toolkit/Transfer/FileFakeStager DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_NODE}

### AGENT LABEL=mss-migrate PROGRAM=Toolkit/Transfer/FileMSSMigrate DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_MSS}
 -mssbackend  'dcache'

#### Custom migration code
#### Create a perl module in your SITECONF (e.g. CustomMSSCheck.pm)
#### with the function &checkFileInMSS defined (args: $pfn, $is_custodial)
### AGENT LABEL=mss-migrate PROGRAM=Toolkit/Transfer/FileMSSMigrate DEFAULT=off
 -db          ${PHEDEX_DBPARAM}
 -nodes       ${PHEDEX_MSS}
 -checkroutine ${SITECONF}/CustomMSSCheck.pm