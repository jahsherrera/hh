﻿# Export-SwisCp.ps1
#Requires -Module @{ ModuleName = 'SwisPowerShell'; ModuleVersion = '3.0.0' }


$ExecutionStartTime = ( Get-Date -Format 's' ).Replace(":", "-")
$ExecutionStartTime = ( Get-Date ).ToString("yyyy-MM-dd")

<#

Yet to be done:
Entities of type:
- Orion.SRM.ProviderCustomProperties
- Orion.SRM.StorageArrayCustomProperties
- Orion.SRM.StorageControllerCustomProperties
- Orion.SRM.StorageControllerPortCustomProperties
- Orion.SRM.VolumeCustomProperties
- Orion.VIM.ClustersCustomProperties
- Orion.VIM.DataCentersCustomProperties
- Orion.VIM.DatastoresCustomProperties
- Orion.VIM.HostsCustomProperties
- Orion.VIM.VirtualMachinesCustomProperties

#>

# Select the location where we want to store the exported files
$ExportPath = ".\CustomPropertyExports"
#region Quick Check to see if the folder exists, and if not, create it
if ( -not ( Test-Path -Path $ExportPath -ErrorAction SilentlyContinue ) ) {
    New-Item -Path $ExportPath -ItemType Directory | Out-Null
}
#endregion Quick Check to see if the folder exists, and if not, create it

# Build the connection to SolarWinds Orion
# This example prompts for the server name/IP and then asks for the username/password combo
if ( -not $SwisConnection ) {
    $SwisHostname = Read-Host -Prompt "Please enter the DNS or IP of your Orion Server"
    $SwisCredential = Get-Credential -Message "Provide the username/password for '$SwisHostname'"

    $SwisConnection = Connect-Swis -Hostname $SwisHostname -Credential $SwisCredential
    # Once we have the connection, we don't need the credentials, so remove them.
    Remove-Variable -Name SwisHostname, SwisCredential -ErrorAction SilentlyContinue
}
# Certificate authentication assumes you are running on the local Orion server, if not, use a different authentication method
#$SwisConnection = Connect-Swis -Hostname 'kmsorion01v.kmsigma.local' -Certificate


# Define a global 'alias' for the Custom Property Lookups
$CpAlias = '[CP]'

# This will retrieve the list of ALL the custom properties, regardless of where they are used
$SwqlCpList = @"
SELECT $( $CpAlias ).Table
     , $( $CpAlias ).Field
     , $( $CpAlias ).DataType
     , $( $CpAlias ).MaxLength
     , $( $CpAlias ).Description
     , $( $CpAlias ).TargetEntity
     , $( $CpAlias ).Mandatory
FROM Orion.CustomProperty AS $( $CpAlias )
ORDER BY $( $CpAlias ).TargetEntity, $( $CpAlias ).Field
"@

# Run the query to get the list of all Custom Properties
$ListOfCps = Get-SwisData -SwisConnection $SwisConnection -Query $SwqlCpList

# Export all of the CP's to have a record
$ListOfCps | Export-Csv -Path ( Join-Path -Path $ExportPath -ChildPath "_CustomProperties.csv" ) -Force -Confirm:$false -NoTypeInformation

# Let's get the list of distinct target entities and just store they as an array of strings
$TargetEntities = $ListOfCps | Select-Object -Property TargetEntity -Unique | Select-Object -ExpandProperty TargetEntity | Sort-Object


#region Identifying Details/Filters/Sorting
<#
  Custom Properties are defined by their resultant Target Entity (Nodes, Interfaces, Reports, etc.)
  Since each table in the SDK has slighly different formatting when it comes to Navigation Properties
  We need to build some 'default' fields to pull, as well as filtering and sorting

  This is done in a series of hastables, so we can 'reference' the specific values by the Target Entity
  This only needs to be done once before we start building the queries
#>



# To do this work we'll need some 'default' fields so we can identify what we're looking at
$BaseCpFields = @{
    "IPAM.GroupsCustomProperties"                     = "$( $CpAlias ).Uri, $( $CpAlias ).GroupNode.FriendlyName, $( $CpAlias ).GroupNode.Address, $( $CpAlias ).GroupNode.CIDR, $( $CpAlias ).GroupNode.GroupTypeText"
    "IPAM.NodesCustomProperties"                      = "$( $CpAlias ).Uri, $( $CpAlias ).IPNode.SysName, $( $CpAlias ).IPNode.DnsBackward, $( $CpAlias ).IPNode.IPAddress, $( $CpAlias ).IPNode.MAC"
    "Orion.AlertConfigurationsCustomProperties"       = "$( $CpAlias ).Alert.Uri + '/CustomProperties' AS [Uri], $( $CpAlias ).Alert.Name"
    "Orion.APM.ApplicationCustomProperties"           = "$( $CpAlias ).Application.Uri + '/CustomProperties' AS [Uri], $( $CpAlias ).Application.Node.Caption, $( $CpAlias ).Application.Name"
    "Orion.GroupCustomProperties"                     = "$( $CpAlias ).[Group].Uri + '/CustomProperties' AS [Uri], $( $CpAlias ).[Group].Name"
    "Orion.NodesCustomProperties"                     = "$( $CpAlias ).Node.Caption, $( $CpAlias ).Uri, $( $CpAlias ).Node.IPAddress"
    "Orion.NPM.InterfacesCustomProperties"            = "$( $CpAlias ).Uri, $( $CpAlias ).Interface.FullName"
    "Orion.ReportsCustomProperties"                   = "$( $CpAlias ).Uri, $( $CpAlias ).Report.Title"
    "Orion.SEUM.RecordingCustomProperties"            = "$( $CpAlias ).Recording.Uri + '/CustomProperties' AS [Uri], $( $CpAlias ).Recording.DisplayName, $( $CpAlias ).Recording.Description"
    "Orion.SEUM.TransactionCustomProperties"          = "$( $CpAlias ).Transaction.Uri + '/CustomProperties' AS [Uri], $( $CpAlias ).Transaction.DisplayName, $( $CpAlias ).Transaction.Description"
    # Assumptions Made About URIs 
    "Orion.SRM.FileShareCustomProperties"             = "$( $CpAlias ).Uri, $( $CpAlias ).FileShares.Name, $( $CpAlias ).FileShares.UserCaption, $( $CpAlias ).FileShares.Caption, $( $CpAlias ).FileShares.Description"
    "Orion.SRM.LUNCustomProperties"                   = "$( $CpAlias ).Uri, $( $CpAlias ).LUNs.Name, $( $CpAlias ).LUNs.UserCaption, $( $CpAlias ).LUNs.Caption, $( $CpAlias ).LUNs.Description"
    "Orion.SRM.PoolCustomProperties"                  = "$( $CpAlias ).Uri, $( $CpAlias ).Pools.Name, $( $CpAlias ).Pools.UserCaption, $( $CpAlias ).Pools.Caption, $( $CpAlias ).Pools.Description"
    "Orion.SRM.ProviderCustomProperties"              = "$( $CpAlias ).Uri, $( $CpAlias ).Providers.Name, $( $CpAlias ).Providers.UserCaption, $( $CpAlias ).Providers.Caption, $( $CpAlias ).Providers.Description"
    "Orion.SRM.StorageArrayCustomProperties"          = "$( $CpAlias ).Uri, $( $CpAlias ).StorageArrays.Name, $( $CpAlias ).StorageArrays.UserCaption, $( $CpAlias ).StorageArrays.Caption, $( $CpAlias ).StorageArrays.Description"
    "Orion.SRM.VolumeCustomProperties"                = "$( $CpAlias ).Uri, $( $CpAlias ).Volumes.Name, $( $CpAlias ).Volumes.UserCaption, $( $CpAlias ).Volumes.Caption, $( $CpAlias ).Volumes.Description"
    "Orion.VIM.DataCentersCustomProperties"           = "$( $CpAlias ).Uri, $( $CpAlias ).DataCenter.Name, $( $CpAlias ).DataCenter.Description"
    # Yet to do
    # Orion.VIM.DatastoresCustomProperties
    # Orion.VIM.HostsCustomProperties
    # Orion.VIM.VirtualMachinesCustomProperties
    "Orion.VolumesCustomProperties"                   = "$( $CpAlias ).Uri, $( $CpAlias ).Volume.Node.Caption AS [Node], $( $CpAlias ).Volume.Description, $( $CpAlias ).Volume.VolumeType"

    # Known Bad Linkage
    #"Orion.SRM.StorageControllerCustomProperties"     = "$( $CpAlias ).Uri, $( $CpAlias ).StorageControllers.Name, $( $CpAlias ).StorageControllers.UserCaption, $( $CpAlias ).StorageControllers.Caption, $( $CpAlias ).StorageControllers.Description"
    #"Orion.SRM.StorageControllerPortCustomProperties" = "$( $CpAlias ).Uri, $( $CpAlias ).StorageControllerPorts.Name, $( $CpAlias ).StorageControllerPorts.DisplayName, $( $CpAlias ).StorageControllerPorts.Description"
    #"Orion.VIM.ClustersCustomProperties"              = "$( $CpAlias ).Uri, $( $CpAlias ).Cluster.Name,  $( $CpAlias ).Cluster.Caption, $( $CpAlias ).Cluster.Description"
}

# Some of the queries would benefit from filtering off some information
$WhereClauses = @{
    "IPAM.GroupsCustomProperties" = "WHERE $( $CpAlias ).GroupNode.CIDR <> 0"
    "Orion.GroupCustomProperties" = "WHERE $( $CpAlias ).[Group].Owner <> 'Maps'"
}

# This sorting is optional, but incredibly helpful
$OrderByClauses = @{
    "IPAM.GroupsCustomProperties"               = "ORDER BY $( $CpAlias ).GroupNode.ParentID, $( $CpAlias ).GroupNode.GroupType"
    "IPAM.NodesCustomProperties"                = "ORDER BY $( $CpAlias ).IpNode.IPAddressN"
    "Orion.AlertConfigurationsCustomProperties" = "ORDER BY $( $CpAlias ).Alert.Name"
    "Orion.APM.ApplicationCustomProperties"     = "ORDER BY $( $CpAlias ).Application.Name, $( $CpAlias ).Application.Node.Caption"
    "Orion.GroupCustomProperties"               = "ORDER BY $( $CpAlias ).[Group].Name"
    "Orion.NodesCustomProperties"               = "ORDER BY $( $CpAlias ).Node.Caption, $( $CpAlias ).Node.IPAddress"
    "Orion.NPM.InterfacesCustomProperties"      = "ORDER BY $( $CpAlias ).Interface.FullName"
    "Orion.ReportsCustomProperties"             = "ORDER BY $( $CpAlias ).Report.Title"
    "Orion.SEUM.RecordingCustomProperties"      = "ORDER BY $( $CpAlias ).Recording.DisplayName"
    "Orion.SEUM.TransactionCustomProperties"    = "ORDER BY $( $CpAlias ).Transaction.DisplayName"
    "Orion.SRM.FileShareCustomProperties"       = "ORDER BY $( $CpAlias ).FileShares.DisplayName"
    "Orion.SRM.LUNCustomProperties"             = "ORDER BY $( $CpAlias ).LUNs.DisplayName"
}
#endregion Identifying Details/Filters/Sorting

# Cycle through each distinct Target Entity type and build a query.
ForEach ( $TargetEntity in $TargetEntities ) {
    # Get the list of fields from each entity type
    $Fields = $ListOfCps | Where-Object { $_.TargetEntity -eq $TargetEntity }
    # Now the $Fields variable contains the names of the fields for the current Target Entity type
    # But, I want to use the Alias, so I'll need to do some clever convertion and then store them as strings (so I can use the -join operator)
    # I also added an alias for CP_(FieldName) so in the exported CSV, it's (hopefully) obvious which fields are custom properties
    $FieldsWithAlias = $Fields | Select-Object -Property @{ Name = 'Field'; Expression = { "$( $CpAlias ).$( $_.Field ) AS CP_$( $_.Field )" } } | Select-Object -ExpandProperty Field
    
    # The query takes the form:
    # SELECT (Base Fields), (Fields From Custom Properties), (Custom Property's URI) FROM (Target Entity) (WHERE/filter clauses) (ORDER BY/sorting clauses)
    if ( $BaseCpFields[$TargetEntity] ) {
        $CpQuery = "SELECT $( $BaseCpFields[$TargetEntity] ), $( $FieldsWithAlias -join ", " ) FROM $TargetEntity AS $CpAlias $( $WhereClauses[$TargetEntity] ) $( $OrderByClauses[$TargetEntity] )"
        Write-Verbose -Message "Execution: $CpQuery"
        $Results = Get-SwisData -SwisConnection $SwisConnection -Query $CpQuery
        if ( $Results ) {
            Write-Host "Exporting $( $Results.Count) record(s) from $TargetEntity to '$( $ExportPath )\$( $TargetEntity ).csv"
            $Results | Export-Csv -Path ( Join-Path -Path $ExportPath -ChildPath "$( $TargetEntity ).csv" ) -Force -Confirm:$false -NoTypeInformation
        }
        else {
            Write-Warning -Message "No entries found for Custom Properties for '$TargetEntity'"
            "No entries found for Custom Properties for '$TargetEntity'" | Out-File -FilePath ( Join-Path -Path $ExportPath -ChildPath "Error_$( $ExecutionStartTime ).log" ) -Append
            "SWQL EXECUTING: $CpQuery" | Out-File -FilePath ( Join-Path -Path $ExportPath -ChildPath "Error_$( $ExecutionStartTime ).log" ) -Append
        }
    }
    else {
        Write-Error -Message "No 'Default' Custom Properties are defined for '$TargetEntity'" -RecommendedAction "Update the script to fix it"
        "No 'Default' Custom Properties are defined for '$TargetEntity'" | Out-File -FilePath ( Join-Path -Path $ExportPath -ChildPath "Error_$( $ExecutionStartTime ).log" ) -Append
    }
}