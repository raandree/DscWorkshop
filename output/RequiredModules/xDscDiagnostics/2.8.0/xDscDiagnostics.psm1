#Region './prefix.ps1' 0
<####################################################################################################################################################
 #  This script enables a user to diagnose errors caused by a DSC operation. In short, the following commands would help you diagnose errors
 #  To get the last 10 operations in DSC that show their Result status (failure , success)         : Get-xDscOperation
 #  To get a list of last n (say, 13) DSC operations                                             : Get-xDscOperation -Newest 13
 #  To see details of the last operation                                                         : Trace-xDscOperation
 #  TO view trace details of the third last operation run                                        : Trace-xDscOperation 3
 #  To view trace details of an operation with Job ID $jID                                       : Trace-xDscOperation -JobID $jID
 #  To View trace details of multiple computers                                                  : Trace-xDscOperation -ComputerName @("PN25113D0891","PN25113D0890")
 #  To enable the debug event channel for DSC                                                    : Update-xDscEventLogStatus -Channel Debug -Status Enabled
 #  To enable the analytic event channel for DSC on another computer (say, with name ABC)        : Update-xDscEventLogStatus -Channel Analytic -Status Enabled -ComputerName ABC
 #  To disable the analytic event channel for DSC on another computer (say, with name ABC)       : Update-xDscEventLogStatus -Channel Analytic -Status Disabled -ComputerName ABC
 #####################################################################################################################################################>

#region Global variables
$script:DscVerboseEventIdsAndPropertyIndex = @{
    4100 = 3
    4117 = 2
    4098 = 3
}
$script:DscLogName = "Microsoft-windows-dsc"
$script:RedirectOutput = $false
$script:TemporaryHtmLocation = "$env:TEMP/dscreport"
$script:SuccessResult = "Success"
$script:FailureResult = "Failure"
$script:ThisCredential = ""
$script:ThisComputerName = $env:COMPUTERNAME
$script:UsingComputerName = $false
$script:FormattingFile = "xDscDiagnosticsFormat.ps1xml"
$script:RunFirstTime = $true
#endregion

#region Cache for events
$script:LatestGroupedEvents = @{ } #Hashtable of "Computername", "GroupedEvents"
$script:LatestEvent = @{ }          #Hashtable of "ComputerName", "LatestEvent logged"
#endregion

$script:azureDscExtensionTargetName = 'Azure DSC Extension'
$script:dscTargetName = 'DSC Node'
$script:windowsTargetName = 'Windows'
$script:dscPullServerTargetName = 'DSC Pull Server'
$script:validTargets = @($script:azureDscExtensionTargetName, $script:dscTargetName, $script:windowsTargetName, $script:dscPullServerTargetName)
$script:defaultTargets = @($script:azureDscExtensionTargetName, $script:dscTargetName, $script:windowsTargetName)

$script:datapointTypeName = 'xDscDiagnostics.DataPoint'
$script:dataPoints = @{
    AzureVmAgentLogs       = @{
        Description = 'Logs from the Azure VM Agent, including all extensions'
        Target      = $script:azureDscExtensionTargetName
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            Copy-Item -Recurse C:\WindowsAzure\Logs $tempPath\WindowsAzureLogs -ErrorAction SilentlyContinue
        }
    } # end data point
    DSCExtension           = @{
        Description = @'
The state of the Azure DSC Extension, including the configuration(s),
configuration data (but not any decryption keys), and included or
generated files.
'@
        Target      = $script:azureDscExtensionTargetName
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            $dirs = @(Get-ChildItem -Path C:\Packages\Plugins\Microsoft.Powershell.*DSC -ErrorAction SilentlyContinue)
            $dir = $null
            if ($dirs.Count -ge 1)
            {
                $dir = $dirs[0].FullName
            }

            if ($dir)
            {
                Write-Verbose -message "Found DSC extension at: $dir" -verbose
                Copy-Item -Recurse $dir $tempPath\DscPackageFolder -ErrorAction SilentlyContinue
                Get-ChildItem "$tempPath\DscPackageFolder" -Recurse | % {
                    if ($_.Extension -ieq '.msu' -or ($_.Extension -ieq '.zip' -and $_.BaseName -like 'Microsoft.Powershell*DSC_*.*.*.*'))
                    {
                        $newFileName = "$($_.FullName).wasHere"
                        Get-ChildItem $_.FullName | Out-String | Out-File $newFileName -Force
                        $_.Delete()
                    }
                }
            }
            else
            {
                Write-Verbose -message 'Did not find DSC extension.' -verbose
            }
        }
    } # end data point
    DscEventLog            = @{
        Description = 'The DSC event log.'
        EventLog    = 'Microsoft-Windows-DSC/Operational'
        Target      = $script:dscTargetName
    } # end data point
    ApplicationEventLog    = @{
        Description = 'The Application event log.'
        EventLog    = 'Application'
        Target      = $script:windowsTargetName
    } # end data point
    SystemEventLog         = @{
        Description = 'The System event log.'
        EventLog    = 'System'
        Target      = $script:windowsTargetName
    } # end data point
    PullServerEventLog     = @{
        Description = 'The DSC Pull Server event log.'
        EventLog    = 'Microsoft-Windows-PowerShell-DesiredStateConfiguration-PullServer/Operational'
        Target      = $script:dscPullServerTargetName
    } # end data point
    ODataEventLog          = @{
        Description = 'The Management OData event log (used by the DSC Pull Server).'
        EventLog    = 'Microsoft-Windows-ManagementOdataService/Operational'
        Target      = $script:dscPullServerTargetName
    } # end data point
    IisBinding             = @{
        Description = 'The Iis Bindings.'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            $width = 900
            Get-WebBinding |
                Select-Object protocol, bindingInformation, sslFlags, ItemXPath |
                    Out-String -Width $width |
                        Out-File -FilePath $tempPath\IisBindings.txt -Width $width
        }
        Target      = $script:dscPullServerTargetName
    } # end data point
    HttpErrLogs            = @{
        Description = 'The HTTPERR logs.'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            mkdir $tempPath\HttpErr > $null
            Copy-Item $env:windir\System32\LogFiles\HttpErr\*.* $tempPath\HttpErr -ErrorAction SilentlyContinue
        }
        Target      = $script:dscPullServerTargetName
    } # end data point
    IISLogs                = @{
        Description = 'The IIS logs.'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            Import-Module WebAdministration
            $logFolder = (Get-WebConfigurationProperty "/system.applicationHost/sites/siteDefaults" -name logfile.directory).Value
            mkdir $tempPath\Inetlogs > $null
            Copy-Item (Join-Path $logFolder *.*) $tempPath\Inetlogs -ErrorAction SilentlyContinue
        }
        Target      = $script:dscPullServerTargetName
    } # end data point
    ServicingLogs          = @{
        Description = 'The Windows Servicing logs, including, WindowsUpdate, CBS and DISM logs.'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            mkdir $tempPath\CBS > $null
            mkdir $tempPath\DISM > $null
            Copy-Item $env:windir\WindowsUpdate.log $tempPath\WindowsUpdate.log -ErrorAction SilentlyContinue
            Copy-Item $env:windir\logs\CBS\*.* $tempPath\CBS -ErrorAction SilentlyContinue
            Copy-Item $env:windir\logs\DISM\*.* $tempPath\DISM -ErrorAction SilentlyContinue
        }
        Target      = $script:windowsTargetName
    } # end data point
    HotfixList             = @{
        Description = 'The output of Get-Hotfix'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            Get-HotFix | Out-String | Out-File  $tempPath\HotFixIds.txt
        }
        Target      = $script:windowsTargetName
    } # end data point
    GetLcmOutput           = @{
        Description = 'The output of Get-DscLocalConfigurationManager'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            $dscLcm = Get-DscLocalConfigurationManager
            $dscLcm | Out-String | Out-File   $tempPath\Get-dsclcm.txt
            $dscLcm | ConvertTo-Json -Depth 10 | Out-File   $tempPath\Get-dsclcm.json
        }
        Target      = $script:dscTargetName
    } # end data point
    VersionInformation     = @{
        Description = 'The PsVersionTable and OS version information'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            $PSVersionTable | Out-String | Out-File   $tempPath\psVersionTable.txt
            Get-CimInstance win32_operatingSystem | select version | out-string | Out-File   $tempPath\osVersion.txt
        }
        Target      = $script:windowsTargetName
    } # end data point
    CertThumbprints        = @{
        Description = 'The local machine cert thumbprints.'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            dir Cert:\LocalMachine\My\ | select -ExpandProperty Thumbprint | out-string | out-file $tempPath\LocalMachineCertThumbprints.txt
        }
        Target      = $script:windowsTargetName
    } # end data point
    DscResourceInventory   = @{
        Description = 'The name, version and path to installed dsc resources.'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            Get-DscResource 2> $tempPath\ResourceErrors.txt | select name, version, path | out-string | out-file $tempPath\ResourceInfo.txt
        }
        Target      = $script:dscTargetName
    } # end data point
    DscConfigurationStatus = @{
        Description = 'The output of Get-DscConfigurationStatus -all'
        ScriptBlock = {
            param ($tempPath)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest
            $statusCommand = get-Command -name Get-DscConfigurationStatus -ErrorAction SilentlyContinue
            if ($statusCommand)
            {
                Get-DscConfigurationStatus -All | out-string | Out-File   $tempPath\get-dscconfigurationstatus.txt
            } }
        Target      = $script:dscTargetName
    } # end data point
}
#EndRegion './prefix.ps1' 236
#Region './Private/Add-ClassTypes.ps1' 0
#Function to Output errors, verbose messages or warning
function Add-ClassTypes
{
    #We don't want to add the same types again and again.
    if ($script:RunFirstTime)
    {
        $pathToFormattingFile = (Join-Path  $PSScriptRoot $script:FormattingFile)
        $ClassDefinitionGroupedEvents = @"
            using System;
            using System.Globalization;
            using System.Collections;
            namespace Microsoft.PowerShell.xDscDiagnostics
            {
                public class GroupedEvents {
                        public int SequenceId;
                        public System.DateTime TimeCreated;
                        public string ComputerName;
                        public Guid? JobID = null;
                        public System.Array AllEvents;
                        public int NumberOfEvents;
                        public System.Array AnalyticEvents;
                        public System.Array DebugEvents;
                        public System.Array NonVerboseEvents;
                        public System.Array VerboseEvents;
                        public System.Array OperationalEvents;
                        public System.Array ErrorEvents;
                        public System.Array WarningEvents;
                        public string Result;

                   }
            }
"@
        $ClassDefinitionTraceOutput = @"
               using System;
               using System.Globalization;
               namespace Microsoft.PowerShell.xDscDiagnostics
               {
                   public enum EventType {
                        DEBUG,
                        ANALYTIC,
                        OPERATIONAL,
                        ERROR,
                        VERBOSE
                   }
                   public class TraceOutput {
                        public EventType EventType;
                        public System.DateTime TimeCreated;
                        public string Message;
                        public string ComputerName;
                        public Guid? JobID = null;
                        public int SequenceID;
                        public System.Diagnostics.Eventing.Reader.EventRecord Event;
                   }
               }

"@
        Add-Type -Language CSharp -TypeDefinition $ClassDefinitionGroupedEvents
        Add-Type -Language CSharp -TypeDefinition $ClassDefinitionTraceOutput
        #Update-TypeData -TypeName TraceOutput -DefaultDisplayPropertySet EventType, TimeCreated, Message
        Update-FormatData  -PrependPath $pathToFormattingFile

        $script:RunFirstTime = $false; #So it doesnt do it the second time.
    }
}
#EndRegion './Private/Add-ClassTypes.ps1' 64
#Region './Private/Clear-DscDiagnosticsCache.ps1' 0
function Clear-DscDiagnosticsCache
{
    LogDscDiagnostics -Verbose "Clearing Diagnostics Cache"
    $script:LatestGroupedEvents = @{ }
    $script:LatestEvent = @{ }
}
#EndRegion './Private/Clear-DscDiagnosticsCache.ps1' 6
#Region './Private/Collect-DataPoint.ps1' 0
# attempts to Collect a datapoint
# Returns $true if it believes it collected the datapoint
function Collect-DataPoint
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [String] $Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [HashTable] $dataPoint,

        [Parameter(Mandatory = $true)]
        [HashTable] $invokeCommandParams
    )

    $collected = $false
    if ($dataPoint.ScriptBlock)
    {
        Write-Verbose -Message "Collecting '$name-$($dataPoint.Description)' using ScripBlock ..."
        Invoke-Command -ErrorAction:Continue @invokeCommandParams -script $dataPoint.ScriptBlock -argumentlist @($tempPath)
        $collected = $true
    }

    if ($dataPoint.EventLog)
    {
        Write-Verbose -Message "Collecting '$name-$($dataPoint.Description)' using Eventlog ..."
        try
        {
            Export-EventLog -Name $dataPoint.EventLog -Path $tempPath @invokeCommandParams
        }
        catch
        {
            Write-Warning "Collecting '$name-$($dataPoint.Description)' failed with the following error:$([System.Environment]::NewLine)$_"
        }

        $collected = $true
    }
    return $collected
}
#EndRegion './Private/Collect-DataPoint.ps1' 42
#Region './Private/Copy-ToZipFileUsingShell.ps1' 0
# Copy files using the Shell.
#
# Note, because this uses shell this will not work on core OSs
# But we only use this on older OSs and in test, so core OS use
# is unlikely
function Copy-ToZipFileUsingShell
{
    param
    (
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                if ($_ -notlike '*.zip')
                {
                    throw 'zipFileName must be *.zip'
                }
                else
                {
                    return $true
                }
            })]
        $zipfilename,

        [string]
        [ValidateScript( {
                if (-not (Test-Path $_))
                {
                    throw 'itemToAdd must exist'
                }
                else
                {
                    return $true
                }
            })]
        $itemToAdd,

        [switch]
        $overWrite
    )
    Set-StrictMode -Version latest
    if (-not (Test-Path $zipfilename) -or $overWrite)
    {
        set-content $zipfilename ('PK' + [char]5 + [char]6 + ("$([char]0)" * 18))
    }
    $app = New-Object -com shell.application
    $zipFile = ( Get-Item $zipfilename ).fullname
    $zipFolder = $app.namespace( $zipFile )
    $itemToAdd = (Resolve-Path $itemToAdd).ProviderPath
    $zipFolder.copyhere( $itemToAdd )
}
#EndRegion './Private/Copy-ToZipFileUsingShell.ps1' 50
#Region './Private/Export-EventLog.ps1' 0
#
# Exports an event log to a file in the path specified
# on the specified session, if the session is not specified
# a session to the local machine will be used
#
function Export-EventLog
{
    [CmdletBinding()]
    param
    (
        [string] $Name,
        [string] $path,
        [System.Management.Automation.Runspaces.PSSession] $Session
    )
    Write-Verbose "Exporting eventlog $name"
    $local = $false
    $invokeCommandParams = @{ }
    if ($Session)
    {
        $invokeCommandParams.Add('Session', $Session);
    }
    else
    {
        $local = $true
    }

    invoke-command -ErrorAction:Continue @invokeCommandParams -script {
        param ($name, $path)
        $ErrorActionPreference = 'stop'
        Set-StrictMode -Version latest
        Write-Debug "Name: $name"

        Write-Debug "Path: $path"
        Write-Debug "windir: $Env:windir"
        $exePath = Join-Path $Env:windir 'system32\wevtutil.exe'
        $exportFileName = "$($Name -replace '/','-').evtx"

        $ExportCommand = "$exePath epl '$Name' '$Path\$exportFileName' /ow:True 2>&1"
        Invoke-expression -command $ExportCommand
    } -argumentlist @($Name, $path)
}
#EndRegion './Private/Export-EventLog.ps1' 41
#Region './Private/Get-AllDscEvents.ps1' 0
#Function to get all dsc events in the event log - not exposed by the module
function Get-AllDscEvents
{
    #If you want a specific channel events, run it as Get-AllDscEvents
    param
    (
        [string[]]$ChannelType = @("Debug" , "Analytic" , "Operational") ,
        $OtherParameters = @{ }
    )

    if ($ChannelType.ToLower().Contains("operational"))
    {
        $operationalEvents = Get-WinEvent -LogName "$script:DscLogName/operational"  @OtherParameters -ea Ignore
        $allEvents = $operationalEvents
    }

    if ($ChannelType.ToLower().Contains("analytic"))
    {
        $analyticEvents = Get-WinEvent -LogName "$script:DscLogName/analytic" -Oldest  -ea Ignore @OtherParameters
        if ($analyticEvents -ne $null)
        {
            #Convert to an array type before adding another type - to avoid the error "Method invocation failed with no op_addition operator"
            $allEvents = [System.Array]$allEvents + $analyticEvents
        }
    }

    if ($ChannelType.ToLower().Contains("debug"))
    {
        $debugEvents = Get-WinEvent -LogName "$script:DscLogName/debug" -Oldest -ea Ignore @OtherParameters
        if ($debugEvents -ne $null)
        {
            $allEvents = [System.Array]$allEvents + $debugEvents

        }
    }

    return $allEvents
}
#EndRegion './Private/Get-AllDscEvents.ps1' 38
#Region './Private/Get-AllGroupedDscEvents.ps1' 0
function Get-AllGroupedDscEvents
{
    $groupedEvents = $null
    $latestEvent = Get-LatestEvent
    LogDscDiagnostics -Verbose "Collecting all events from the DSC logs"
    if ($script:LatestEvent[$script:ThisComputerName])
    {
        #Check if there were any differences between the latest event and the latest event in th ecache
        $compareResult = Compare-Object $script:LatestEvent[$script:ThisComputerName] $latestEvent -Property TimeCreated, Message
        #Compare object result will be null if they're both equal
        if (($compareResult -eq $null) -and $script:LatestGroupedEvents[$script:ThisComputerName])
        {
            # this means no new events were generated and you can use the event cache.
            $groupedEvents = $script:LatestGroupedEvents[$script:ThisComputerName]
            return $groupedEvents
        }

    }
    #if cache needs to be replaced, it will not return in the previous line and will come here.

    #Save it to cache
    $allEvents = Get-AllDscEvents
    if (!$allEvents)
    {
        LogDscDiagnostics -Error "Error : Could not find any events. Either a DSC operation has not been run, or the event logs are turned off . Please ensure the event logs are turned on in DSC. To set an event log, run the command wevtutil Set-Log <channelName> /e:true, example: wevtutil set-log 'Microsoft-Windows-Dsc/Operational' /e:true /q:true"
        return
    }
    $groupedEvents = $allEvents | Group-Object {
        $_.Properties[0].Value
    }

    $script:LatestEvent[$script:ThisComputerName] = $latestEvent
    $script:LatestGroupedEvents[$script:ThisComputerName] = $groupedEvents


    #group based on their Job Ids
    return $groupedEvents
}
#EndRegion './Private/Get-AllGroupedDscEvents.ps1' 38
#Region './Private/Get-DscErrorMessage.ps1' 0
function Get-DscErrorMessage
{
    param (<#[System.Diagnostics.Eventing.Reader.EventRecord[]]#>$ErrorRecords)
    $cimErrorId = 4131

    $errorText = ""
    foreach ($Record in $ErrorRecords)
    {
        #go through each record, and get the single error message required for that record.
        $outputErrorMessage = Get-SingleRelevantErrorMessage -errorEvent $Record
        if ($Record.Id -eq $cimErrorId)
        {
            $errorText = "$outputErrorMessage $errorText"
        }
        else
        {
            $errorText = "$errorText $outputErrorMessage"
        }
    }
    return  $errorText

}
#EndRegion './Private/Get-DscErrorMessage.ps1' 22
#Region './Private/Get-DscLatestJobId.ps1' 0
#Gets the JOB ID of the most recently executed script.
function Get-DscLatestJobId
{
    #Collect operational events , they're ordered from newest to oldest.

    $allEvents = Get-WinEvent -LogName "$script:DscLogName/operational" -MaxEvents 2 -ea Ignore
    if ($allEvents -eq $null)
    {
        return "NOJOBID"
    }
    $latestEvent = $allEvents[0] #Since it extracts it in a sorted order.

    #Extract just the jobId from the string like : Job : {<jobid>}
    #$jobInfo = (((($latestEvent.Message -split (":",2))[0] -split "job {")[1]) -split "}")[0]
    $jobInfo = $latestEvent.Properties[0].value

    return $jobInfo.ToString()
}
function Get-LatestEvent
{
    $allEvents = Get-WinEvent -LogName "$script:DscLogName/operational" -MaxEvents 2 -ea Ignore
    if ($allEvents -eq $null)
    {
        return "NOEVENT"
    }
    $latestEvent = $allEvents[0] #Since it extracts it in a sorted order.
    return $latestEvent
}
#EndRegion './Private/Get-DscLatestJobId.ps1' 28
#Region './Private/Get-DscOperationInternal.ps1' 0
#Internal function called by Get-xDscOperation
function Get-DscOperationInternal
{
    param
    (
        [UInt32]$Newest = 10
    )
    #Groupo all events
    $groupedEvents = Get-AllGroupedDscEvents

    $DiagnosedGroup = $groupedEvents

    #Define the type that you want the output in

    $index = 1
    foreach ($singleRecordInGroupedEvents in $DiagnosedGroup)
    {
        $singleOutputRecord = Split-SingleDscGroupedRecord -singleRecordInGroupedEvents $singleRecordInGroupedEvents -index $index
        $singleOutputRecord
        if ($index -ge $Newest)
        {
            break;
        }
        $index++
    }
}
#EndRegion './Private/Get-DscOperationInternal.ps1' 26
#Region './Private/Get-FolderAsZip.ps1' 0
#
# Zips the specified folder
# returns either the path or the contents of the zip files based on the returnvalue parameterer
# When using the contents, Use set-content to create a zip file from it.
# on the specified session, if the session is not specified
# a session to the local machine will be used
#
#
function Get-FolderAsZip
{
    [CmdletBinding()]
    param
    (
        [string]$sourceFolder,
        [string] $destinationPath,
        [System.Management.Automation.Runspaces.PSSession] $Session,
        [ValidateSet('Path', 'Content')]
        [string] $ReturnValue = 'Path',
        [string] $filename
    )

    $local = $false
    $invokeCommandParams = @{ }
    if ($Session)
    {
        $invokeCommandParams.Add('Session', $Session);
    }
    else
    {
        $local = $true
    }

    $attempts = 0
    $gotZip = $false
    while ($attempts -lt 5 -and !$gotZip)
    {
        $attempts++
        $resultTable = invoke-command -ErrorAction:Continue @invokeCommandParams -script {
            param ($logFolder, $destinationPath, $fileName, $ReturnValue)
            $ErrorActionPreference = 'stop'
            Set-StrictMode -Version latest


            $tempPath = Join-path $env:temp ([system.io.path]::GetRandomFileName())
            if (!(Test-Path $tempPath))
            {
                mkdir $tempPath > $null
            }

            $sourcePath = Join-path $logFolder '*'
            Copy-Item -Recurse $sourcePath $tempPath -ErrorAction SilentlyContinue

            $content = $null
            $caughtError = $null
            try
            {
                # Generate an automatic filename if filename is not supplied
                if (!$fileName)
                {
                    $fileName = "$([System.IO.Path]::GetFileName($logFolder))-$((Get-Date).ToString('yyyyMMddhhmmss')).zip"
                }

                if ($destinationPath)
                {
                    $zipFile = Join-Path $destinationPath $fileName

                    if (!(Test-Path $destinationPath))
                    {
                        mkdir $destinationPath > $null
                    }
                }
                else
                {
                    $zipFile = Join-Path ([IO.Path]::GetTempPath()) ('{0}.zip' -f $fileName)
                }

                # Choose appropriate implementation based on CLR version
                if ($PSVersionTable.CLRVersion.Major -lt 4)
                {
                    Copy-ToZipFileUsingShell -zipfilename $zipFile -itemToAdd $tempPath
                    $content = Get-Content $zipFile | Out-String
                }
                else
                {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem > $null
                    [IO.Compression.ZipFile]::CreateFromDirectory($tempPath, $zipFile) > $null
                    $content = Get-Content -Raw $zipFile
                }
            }
            catch [Exception]
            {
                $caughtError = $_
            }

            if ($ReturnValue -eq 'Path')
            {
                # Don't return content if we don't need it
                return @{
                    Content     = $null
                    Error       = $caughtError
                    zipFilePath = $zipFile
                }
            }
            else
            {
                return @{
                    Content     = $content
                    Error       = $caughtError
                    zipFilePath = $zipFile
                }
            }
        } -argumentlist @($sourceFolder, $destinationPath, $fileName, $ReturnValue) -ErrorVariable zipInvokeError


        if ($zipInvokeError -or $resultTable.Error)
        {
            if ($attempts -lt 5)
            {
                Write-Debug "An error occured trying to zip $sourceFolder .  Will retry..."
                Start-Sleep -Seconds $attempts
            }
            else
            {
                if ($resultTable.Error)
                {
                    $lastError = $resultTable.Error
                }
                else
                {
                    $lastError = $zipInvokeError[0]
                }

                Write-Warning "An error occured trying to zip $sourceFolder .  Aborting."
                Write-ErrorInfo -ErrorObject $lastError -WriteWarning

            }
        }
        else
        {
            $gotZip = $true
        }
    }

    if ($ReturnValue -eq 'Path')
    {
        $result = $resultTable.zipFilePath
    }
    else
    {
        $result = $resultTable.content
    }

    return $result
}
#EndRegion './Private/Get-FolderAsZip.ps1' 154
#Region './Private/Get-MessageFromEvent.ps1' 0
function Get-MessageFromEvent($EventRecord , [switch]$verboseType)
{
    #You need to remove the job ID and send back the message
    if ($EventRecord.Id -in $script:DscVerboseEventIdsAndPropertyIndex.Keys -and $verboseType)
    {
        $requiredIndex = $script:DscVerboseEventIdsAndPropertyIndex[$($EventRecord.Id)]
        return $EventRecord.Properties[$requiredIndex].Value
    }

    $NonJobIdText = ($EventRecord.Message -split ([Environment]::NewLine , 2))[1]


    return $NonJobIdText
}
#EndRegion './Private/Get-MessageFromEvent.ps1' 14
#Region './Private/Get-SingleDscOperation.ps1' 0
#This function gets all the DSC runs that are recorded into the event log.
function Get-SingleDscOperation
{
    #If you specify a sequence ID, then the diagnosis will be for that sequence ID.
    param
    (
        [Uint32]$indexInArray = 0,
        [Guid]$JobId
    )

    #Get all events
    $groupedEvents = Get-AllGroupedDscEvents
    if (!$groupedEvents)
    {
        return
    }
    #If there is a job ID present, ignore the IndexInArray, search based on jobID
    if ($JobId)
    {
        LogDscDiagnostics -Verbose "Looking at Event Trace for the given Job ID $JobId"
        $indexInArray = 0;
        foreach ($eventGroup in $groupedEvents)
        {
            #Check if the Job ID is present in any
            if ($($eventGroup.Name) -match $JobId)
            {
                break;
            }
            $indexInArray ++
        }

        if ($indexInArray -ge $groupedEvents.Count)
        {
            #This means the job id doesn't exist
            LogDscDiagnostics -Error "The Job ID Entered $JobId, does not exist among the dsc operations. To get a list of previously run DSC operations, run this command : Get-xDscOperation"
            return
        }
    }

    $requiredRecord = $groupedEvents[$indexInArray]

    if ($requiredRecord -eq $null)
    {
        LogDscDiagnostics -Error "Could not obtain the required record! "
        return
    }
    $errorText = "[None]"
    $thisRunsOutputEvents = Split-SingleDscGroupedRecord -singleRecordInGroupedEvents $requiredRecord -index $indexInArray

    $thisRunsOutputEvents
}
#EndRegion './Private/Get-SingleDscOperation.ps1' 51
#Region './Private/Get-SingleRelevantErrorMessage.ps1' 0
function Get-SingleRelevantErrorMessage(<#[System.Diagnostics.Eventing.Reader.EventRecord]#>$errorEvent)
{
    $requiredPropertyIndex = @{
        4116 = 2;
        4131 = 1;
        4183 = -1; #means full message
        4129 = -1;
        4192 = -1;
        4193 = -1;
        4194 = -1;
        4185 = -1;
        4097 = 6;
        4103 = 5;
        4104 = 4
    }
    $cimErrorId = 4131
    $errorText = ""
    $outputErrorMessage = ""
    $eventId = $errorEvent.Id
    $propertyIndex = $requiredPropertyIndex[$eventId]
    if ($propertyIndex -and $propertyIndex -ne -1)
    {
        #This means You need just the property from the indices hash
        $outputErrorMessage = $errorEvent.Properties[$propertyIndex].Value
    }
    else
    {
        $outputErrorMessage = Get-MessageFromEvent -EventRecord $errorEvent
    }
    return $outputErrorMessage

}
#EndRegion './Private/Get-SingleRelevantErrorMessage.ps1' 32
#Region './Private/Get-WinEvent.ps1' 0
#Wrapper over Get-WinEvent, that will call into a computer if required.
function Get-WinEvent
{
    $resultArray = ""
    try
    {
        if ($script:UsingComputerName)
        {
            if ($script:ThisCredential)
            {
                $resultArray = Microsoft.PowerShell.Diagnostics\Get-WinEvent @args -ComputerName $script:ThisComputerName -Credential $script:ThisCredential
            }
            else
            {
                $resultArray = Microsoft.PowerShell.Diagnostics\Get-WinEvent @args -ComputerName $script:ThisComputerName
            }
        }
        else
        {
            $resultArray = Microsoft.PowerShell.Diagnostics\Get-WinEvent @args
        }
    }
    catch
    {
        LogDscDiagnostics -Error "Get-Winevent failed with error : $_ "
        throw "Cannot read events from computer $script:ThisComputerName. Please check if the firewall is enabled. Run this command in the remote machine to enable firewall for remote administration : New-NetFirewallRule -Name 'Service RemoteAdmin' -Action Allow "
    }

    return $resultArray
}
#EndRegion './Private/Get-WinEvent.ps1' 30
#Region './Private/LogDscDiagnostics.ps1' 0

function LogDscDiagnostics
{
    param ($text , [Switch]$Error , [Switch]$Verbose , [Switch]$Warning)
    $formattedText = "XDscDiagnostics : $text"
    if ($Error)
    {
        Write-Error   $formattedText
    }
    elseif ($Verbose)
    {
        Write-Verbose $formattedText
    }

    elseif ($Warning)
    {
        Write-Warning $formattedText
    }

}
#EndRegion './Private/LogDscDiagnostics.ps1' 20
#Region './Private/Split-SingleDscGroupedRecord.ps1' 0
function Split-SingleDscGroupedRecord
{
    param
    (
        $singleRecordInGroupedEvents,
        $index)

    #$singleOutputRecord = New-Object psobject
    $status = $script:SuccessResult
    $errorEvents = @()
    $col_AllEvents = @()
    $col_verboseEvents = @()
    $col_analyticEvents = @()
    $col_debugEvents = @()
    $col_operationalEvents = @()
    $col_warningEvents = @()
    $col_nonVerboseEvents = @()

    #We want to now add a column for each event that says "staus as success or failure"
    $oneGroup = $singleRecordInGroupedEvents.Group
    $column_Time = $oneGroup[0].TimeCreated
    $oneGroup |
        % {
            $thisEvent = $_
            $thisType = ""
            $timeCreatedOfEvent = $_.TimeCreated

            if ($_.level -eq 2) #which means there's an error
            {
                $status = "$script:FailureResult"
                $errorEvents += $_
                $thisType = [Microsoft.PowerShell.xDscDiagnostics.EventType]::ERROR

            }
            elseif ($_.LevelDisplayName -like "warning")
            {
                $col_warningEvents += $_
            }
            if ($_.ContainerLog.endsWith("operational"))
            {
                $col_operationalEvents += $_ ;
                $col_nonVerboseEvents += $_

                #Only if its not an error message, mark it as OPerational tag
                if (!$thisType)
                {
                    $thisType = [Microsoft.PowerShell.xDscDiagnostics.EventType]::OPERATIONAL
                }
            }
            elseif ($_.ContainerLog.endsWith("debug"))
            {
                $col_debugEvents += $_ ; $thisType = [Microsoft.PowerShell.xDscDiagnostics.EventType]::DEBUG
            }
            elseif ($_.ContainerLog.endsWith("analytic"))
            {
                $col_analyticEvents += $_
                if ($_.Id -in $script:DscVerboseEventIdsAndPropertyIndex.Keys)
                {
                    $col_verboseEvents += $_
                    $thisType = [Microsoft.PowerShell.xDscDiagnostics.EventType]::VERBOSE

                }
                else
                {
                    $col_nonVerboseEvents += $_
                    $thisType = [Microsoft.PowerShell.xDscDiagnostics.EventType]::ANALYTIC

                }
            }
            $eventMessageFromEvent = Get-MessageFromEvent $thisEvent -verboseType
            #Add event with its tag

            $thisObject = New-Object PSobject -Property @{
                TimeCreated = $timeCreatedOfEvent
                EventType = $thisType
                Event = $thisEvent
                Message = $eventMessageFromEvent
            }
            $defaultProperties = @('TimeCreated' , 'Message' , 'EventType')
            $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet' , [string[]]$defaultProperties)
            $defaultMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
            $thisObject | Add-Member MemberSet PSStandardMembers $defaultMembers

            $col_AllEvents += $thisObject

        }

    $jobIdWithoutParenthesis = ($($singleRecordInGroupedEvents.Name).split('{}'))[1] #Remove paranthesis that comes in the job id
    if (!$jobIdWithoutParenthesis)
    {
        $jobIdWithoutParenthesis = $null
    }

    $singleOutputRecord = New-Object Microsoft.PowerShell.xDscDiagnostics.GroupedEvents -property @{
        SequenceID     = $index;
        ComputerName   = $script:ThisComputerName;
        JobId          = $jobIdWithoutParenthesis;
        TimeCreated    = $column_Time;
        Result         = $status;
        NumberOfEvents = $singleRecordInGroupedEvents.Count;
    }

    $singleOutputRecord.AllEvents = $col_AllEvents | Sort-Object TimeCreated;
    $singleOutputRecord.AnalyticEvents = $col_analyticEvents ;
    $singleOutputRecord.WarningEvents = $col_warningEvents | Sort-Object TimeCreated ;
    $singleOutputRecord.OperationalEvents = $col_operationalEvents;
    $singleOutputRecord.DebugEvents = $col_debugEvents ;
    $singleOutputRecord.VerboseEvents = $col_verboseEvents  ;
    $singleOutputRecord.NonVerboseEvents = $col_nonVerboseEvents | Sort-Object TimeCreated;
    $singleOutputRecord.ErrorEvents = $errorEvents;

    return $singleOutputRecord
}
#EndRegion './Private/Split-SingleDscGroupedRecord.ps1' 113
#Region './Private/Test-ContainerParameter.ps1' 0
#
# Tests if a parameter is a container, to be used in a ValidateScript attribute
#
function Test-ContainerParameter
{
    [CmdletBinding()]
    param
    (
        [string] $Path,
        [string] $Name = 'Path'
    )

    if (!(Test-Path $Path -PathType Container))
    {
        throw "$Name parameter must be a valid container."
    }

    return $true
}
#EndRegion './Private/Test-ContainerParameter.ps1' 19
#Region './Private/Test-DscEventLogStatus.ps1' 0
#  Function to prompt the user to set an event log, for the channel passed in as parameter
function Test-DscEventLogStatus
{
    param ($Channel = "Analytic")
    $LogDetails = Get-WinEvent -ListLog "$script:DscLogName/$Channel"
    if ($($LogDetails.IsEnabled))
    {
        return $true
    }
    LogDscDiagnostics -Warning "The $Channel log is not enabled. To enable it, please run the following command: `n        Update-xDscEventLogStatus -Channel $Channel -Status Enabled `nFor more help on this cmdlet run Get-Help Update-xDscEventLogStatus"

    return $false
}
#EndRegion './Private/Test-DscEventLogStatus.ps1' 13
#Region './Private/Test-PullServerPresent.ps1' 0
#
# Verifies if Pull Server is installed on this machine
#
function Test-PullServerPresent
{
    [CmdletBinding()]

    $isPullServerPresent = $false;

    $isServerSku = Test-ServerSku

    if ($isServerSku)
    {
        Write-Verbose "This is a Server machine"
        $website = Get-WebSite PSDSCPullServer -erroraction silentlycontinue
        if ($website -ne $null)
        {
            $isPullServerPresent = $true
        }
    }

    Write-Verbose "This is not a pull server"
    return $isPullServerPresent
}
#EndRegion './Private/Test-PullServerPresent.ps1' 24
#Region './Private/Test-ServerSku.ps1' 0
#
# Checks if this machine is a Server SKU
#
function Test-ServerSku
{
    [CmdletBinding()]
    $os = Get-CimInstance -ClassName  Win32_OperatingSystem
    $isServerSku = ($os.ProductType -ne 1)
}
#EndRegion './Private/Test-ServerSku.ps1' 9
#Region './Private/Trace-DscOperationInternal.ps1' 0
function Trace-DscOperationInternal
{
    [cmdletBinding()]
    param
    (
        [UInt32]$SequenceID = 1, #latest is by default
        [Guid]$JobId

    )


    #region VariableChecks
    $indexInArray = ($SequenceId - 1); #Since it is indexed from 0

    if ($indexInArray -lt 0)
    {
        LogDscDiagnostics -Error "Please enter a valid Sequence ID . All sequence IDs can be seen after running command Get-xDscOperation . " -ForegroundColor Red
        return
    }
    $null = Test-DscEventLogStatus -Channel "Analytic"
    $null = Test-DscEventLogStatus -Channel "Debug"

    #endregion

    #First get the whole object set of that operation
    $thisRUnsOutputEvents = ""
    if (!$JobId)
    {
        $thisRunsOutputEvents = Get-SingleDscOperation -IndexInArray $indexInArray
    }
    else
    {
        $thisRunsOutputEvents = Get-SingleDscOperation -IndexInArray $indexInArray -JobId $JobId
    }
    if (!$thisRunsOutputEvents)
    {
        return;
    }

    #Now we play with it.
    $result = $thisRunsOutputEvents.Result

    #Parse the error events and store them in error text.
    $errorEvents = $thisRunsOutputEvents.ErrorEvents
    $errorText = Get-DscErrorMessage -ErrorRecords  $errorEvents

    #Now Get all logs which are non verbose
    $nonVerboseMessages = @()

    $allEventMessageObject = @()
    $thisRunsOutputEvents.AllEvents |
        % {
            $ThisEvent = $_.Event
            $ThisMessage = $_.Message
            $ThisType = $_.EventType
            $ThisTimeCreated = $_.TimeCreated
            #Save a hashtable as a message value
            if (!$thisRunsOutputEvents.JobId)
            {
                $thisJobId = $null
            }
            else
            {
                $thisJobId = $thisRunsOutputEvents.JobId
            }
            $allEventMessageObject += New-Object Microsoft.PowerShell.xDscDiagnostics.TraceOutput -Property @{
                EventType = $ThisType
                TimeCreated = $ThisTimeCreated
                Message = $ThisMessage
                ComputerName = $script:ThisComputerName
                JobID = $thisJobId
                SequenceID = $SequenceID
                Event = $ThisEvent
            }
        }

    return $allEventMessageObject

}
#EndRegion './Private/Trace-DscOperationInternal.ps1' 79
#Region './Private/Write-ProgressMessage.ps1' 0
function Write-ProgressMessage
{
    [CmdletBinding()]
    param ([string]$Status, [int]$PercentComplete, [switch]$Completed)

    Write-Progress -Activity 'Get-AzureVmDscDiagnostics' @PSBoundParameters
    Write-Verbose -message $status
}
#EndRegion './Private/Write-ProgressMessage.ps1' 8
#Region './Public/Get-xDscConfigurationDetail.ps1' 0
# Gets the Json details for a configuration status
function Get-xDscConfigurationDetail
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValuefromPipeline = $true, ParameterSetName = "ByValue")]
        [ValidateScript( {
                if ($_.CimClass.CimClassName -eq 'MSFT_DSCConfigurationStatus')
                {
                    return $true
                }
                else
                {
                    throw 'Must be a configuration status object'
                }
            })]
        $ConfigurationStatus,

        [Parameter(Mandatory = $true, ParameterSetName = "ByJobId")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                [System.Guid] $jobGuid = [System.Guid]::Empty
                if ([System.Guid]::TryParse($_, ([ref] $jobGuid)))
                {
                    return $true
                }
                else
                {
                    throw 'JobId must be a valid GUID'
                }
            })]
        [string] $JobId
    )
    process
    {
        [bool] $hasJobId = $false
        [string] $id = ''
        if ($null -ne $ConfigurationStatus)
        {
            $id = $ConfigurationStatus.JobId
        }
        else
        {
            [System.Guid] $jobGuid = [System.Guid]::Parse($JobId)
            # ensure the job id string has the expected leading and trailing '{', '}' characters.
            $id = $jobGuid.ToString('B')
        }

        $detailsFiles = Get-ChildItem -Path "$env:windir\System32\Configuration\ConfigurationStatus\$id-?.details.json" -ErrorAction 'SilentlyContinue'
        if ($detailsFiles)
        {
            foreach ($detailsFile in $detailsFiles)
            {
                Write-Verbose -Message "Getting details from: $($detailsFile.FullName)"
                (Get-Content -Encoding Unicode -raw $detailsFile.FullName) |
                    ConvertFrom-Json |
                        Foreach-Object {
                            Write-Output $_
                        }
            }
        }
        elseif ($null -ne $ConfigurationStatus)
        {
            if ($($ConfigurationStatus.type) -eq 'Consistency')
            {
                Write-Warning -Message "DSC does not produced details for job type: $($ConfigurationStatus.type); id: $($ConfigurationStatus.JobId)"
            }
            else
            {
                Write-Error -Message "Cannot find detail for job type: $($ConfigurationStatus.type); id: $($ConfigurationStatus.JobId)"
            }
        }
        else
        {
            throw "Cannot find configuration details for job $id"
        }
    }
}
#EndRegion './Public/Get-xDscConfigurationDetail.ps1' 79
#Region './Public/Get-xDscDiagnosticsZipDataPoint.ps1' 0
# Returns a list of datapoints which will be collected by
# New-xDscDiagnosticsZip
function Get-xDscDiagnosticsZipDataPoint
{
    foreach ($key in $script:dataPoints.Keys)
    {
        $dataPoint = $script:dataPoints.$key
        $dataPointObj = ([PSCustomObject] @{
            Name = $key
            Description = $dataPoint.Description
            Target = $dataPoint.Target
        })
        $dataPointObj.pstypenames.Clear()
        $dataPointObj.pstypenames.Add($script:datapointTypeName)
        Write-Output $dataPointObj
    }
}
#EndRegion './Public/Get-xDscDiagnosticsZipDataPoint.ps1' 17
#Region './Public/Get-xDscOperation.ps1' 0
<#
.SYNOPSIS
Gives a list of all DSC operations that were executed . Each DSC operation has sequence Id information , and job id information
It returns a list of objects, each of which contain information on a distinct DSC operation . Here a DSC operation is referred to any single DSC execution, such as start-dscconfiguration, test-dscconfiguration etc. These will log events with a unique jobID (guid) identifying the DSC operation.

When you run Get-xDscOperation, you will see a list of past DSC operations , and you could use the following details from the output to trace any of them individually.
- Job ID : By using this GUID, you can search for the events in Event viewer, or run Trace-xDscOperation -jobID <required Jobid> to obtain all event details of that operation
- Sequence Id : By using this identifier, you could run Trace-xDscOperation <sequenceId> to get all event details of that particular dsc operation.


.DESCRIPTION
This will list all the DSC operations that were run in the past in the computer. By Default, it will list last 10 operations.

.PARAMETER Newest
By default 10 last DSC operations are pulled out from the event logs. To have more, you could use enter another number with this parameter.a PS Object with all the information output to the screen can be navigated by the user as required.


.EXAMPLE
Get-xDscOperation 20
Lists last 20 operations

.EXAMPLE
Get-xDscOperation -ComputerName @("XYZ" , "ABC") -Credential $cred
Lists operations for the array of computernames passed in.
#>

function Get-xDscOperation
{
    [cmdletBinding()]
    param
    (
        [UInt32]$Newest = 10,
        [String[]]$ComputerName,
        [pscredential]$Credential
    )
    Add-ClassTypes
    if ($ComputerName)
    {
        $script:UsingComputerName = $true
        $args = $PSBoundParameters
        $null = $args.Remove("ComputerName")
        $null = $args.Remove("Credential")

        foreach ($thisComputerName in $ComputerName)
        {
            LogDscDiagnostics -Verbose "Gathering logs for Computer $thisComputerName"
            $script:ThisComputerName = $thisComputerName
            $script:ThisCredential = $Credential
            Get-DscOperationInternal  @PSBoundParameters

        }
    }
    else
    {
        $script:ThisComputerName = $env:COMPUTERNAME
        Get-DscOperationInternal @PSBoundParameters
        $script:UsingComputerName = $false
    }
}
#EndRegion './Public/Get-xDscOperation.ps1' 59
#Region './Public/New-xDscDiagnosticsZip.ps1' 0
#
# Gathers diagnostics for DSC and the DSC Extension into a zipfile
# if specified, in the specified path
# if specified, in the specified filename
# on the specified session, if the session is not specified
# a session to the local machine will be used
#
function New-xDscDiagnosticsZip
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'default')]
    [Alias('Get-xDscDiagnosticsZip')]
    param
    (
        [Parameter(ParameterSetName = 'default')]
        [Parameter(ParameterSetName = 'includedDataPoints')]
        [Parameter(ParameterSetName = 'includedTargets')]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(ParameterSetName = 'default')]
        [Parameter(ParameterSetName = 'includedDataPoints')]
        [Parameter(ParameterSetName = 'includedTargets')]
        [string] $destinationPath,

        [Parameter(ParameterSetName = 'default')]
        [Parameter(ParameterSetName = 'includedDataPoints')]
        [Parameter(ParameterSetName = 'includedTargets')]
        [string] $filename,

        [Parameter(ParameterSetName = 'includedDataPoints', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            foreach ($point in $_)
            {
                if ($_.pstypenames -notcontains $script:datapointTypeName)
                {
                    throw 'IncluedDataPoint must be an array of xDscDiagnostics datapoint objects.'
                }
            }

            return $true
        })]
        [object[]] $includedDataPoint
    )
    dynamicparam
    {
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        $dataPointTargetsParametereAttribute = [System.Management.Automation.ParameterAttribute]::new()
        $dataPointTargetsParametereAttribute.Mandatory = $true
        $dataPointTargetsParametereAttribute.ParameterSetName = 'includedTargets'
        $attributeCollection.Add($dataPointTargetsParametereAttribute)

        $validateSetAttribute = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$script:validTargets)

        $attributeCollection.Add($validateSetAttribute)
        $dataPointTargetsParam = New-Object System.Management.Automation.RuntimeDefinedParameter('DataPointTarget', [String[]], $attributeCollection)

        $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $paramDictionary.Add('DataPointTarget', $dataPointTargetsParam)
        return $paramDictionary
    }

    process
    {
        [string[]] $dataPointTarget = $PSBoundParameters.DataPointTarget
        $dataPointsToCollect = @{ }
        switch ($pscmdlet.ParameterSetName)
        {
            "includedDataPoints"
            {
                foreach ($dataPoint in $includedDataPoint)
                {
                    $dataPointsToCollect.Add($dataPoint.Name, $script:dataPoints.($dataPoint.Name))
                }
            }
            "includedTargets"
            {
                foreach ($key in $script:dataPoints.keys)
                {
                    $dataPoint = $script:dataPoints.$key
                    if ($dataPointTarget -icontains $dataPoint.Target)
                    {
                        $dataPointsToCollect.Add($key, $dataPoint)
                    }
                }
            }
            default
            {
                foreach ($key in $script:dataPoints.keys)
                {
                    $dataPoint = $script:dataPoints.$key
                    if ($script:defaultTargets -icontains $dataPoint.Target)
                    {
                        $dataPointsToCollect.Add($key, $dataPoint)
                    }
                }
            }
        }

        $local = $false
        $invokeCommandParams = @{ }
        if ($Session)
        {
            $invokeCommandParams.Add('Session', $Session);
        }
        else
        {
            $local = $true
        }

        $privacyConfirmation = "Collecting the following information, which may contain private/sensative details including:"
        foreach ($key in $dataPointsToCollect.Keys)
        {
            $dataPoint = $dataPointsToCollect.$key
            $privacyConfirmation += [System.Environment]::NewLine
            $privacyConfirmation += ("`t{0}" -f $dataPoint.Description)
        }
        $privacyConfirmation += [System.Environment]::NewLine
        $privacyConfirmation += "This tool is provided for your convience, to ensure all data is collected as quickly as possible."
        $privacyConfirmation += [System.Environment]::NewLine
        $privacyConfirmation += "Are you sure you want to continue?"

        if ($pscmdlet.ShouldProcess($privacyConfirmation))
        {
            $tempPath = invoke-command -ErrorAction:Continue @invokeCommandParams -script {
                $ErrorActionPreference = 'stop'
                Set-StrictMode -Version latest
                $tempPath = Join-path $env:temp ([system.io.path]::GetRandomFileName())
                if (!(Test-Path $tempPath))
                {
                    mkdir $tempPath > $null
                }
                return $tempPath
            }
            Write-Verbose -message "tempPath: $tempPath"

            $collectedPoints = 0
            foreach ($key in $dataPointsToCollect.Keys)
            {
                $dataPoint = $dataPointsToCollect.$key
                if (!$dataPoint.Skip -or !(&$dataPoint.skip))
                {
                    Write-ProgressMessage  -Status "Collecting '$($dataPoint.Description)' ..." -PercentComplete ($collectedPoints / $script:dataPoints.Count)
                    $collected = Collect-DataPoint -dataPoint $dataPoint -invokeCommandParams $invokeCommandParams -Name $key
                    if (!$collected)
                    {
                        Write-Warning "Did not collect  '$($dataPoint.Description)'"
                    }
                }
                else
                {
                    Write-Verbose -Message "Skipping collecting '$($dataPoint.Description)' ..."
                }
                $collectedPoints ++
            }

            if (!$destinationPath)
            {
                Write-ProgressMessage  -Status 'Getting destinationPath ...' -PercentComplete 74
                $destinationPath = invoke-command -ErrorAction:Continue @invokeCommandParams -script {
                    $ErrorActionPreference = 'stop'
                    Set-StrictMode -Version latest
                    Join-path $env:temp ([system.io.path]::GetRandomFileName())
                }
            }

            Write-Debug -message "destinationPath: $destinationPath" -verbose
            $zipParams = @{
                sourceFolder    = $tempPath
                destinationPath = $destinationPath
                Session         = $session
                fileName        = $fileName
            }

            Write-ProgressMessage  -Status 'Zipping files ...' -PercentComplete 75
            if ($local)
            {
                $zip = Get-FolderAsZip @zipParams
                $zipPath = $zip
            }
            else
            {
                $zip = Get-FolderAsZip @zipParams -ReturnValue 'Content'
                if (!(Test-Path $destinationPath))
                {
                    mkdir $destinationPath > $null
                }
                $zipPath = (Join-path $destinationPath "$($session.ComputerName)-dsc-diags-$((Get-Date).ToString('yyyyMMddhhmmss')).zip")
                set-content -path $zipPath -value $zip
            }

            Start-Process $destinationPath
            Write-Verbose -message "Please send this zip file the engineer you have been working with.  The engineer should have emailed you instructions on how to do this: $zipPath" -verbose
            Write-ProgressMessage  -Completed
            return $zipPath
        }

    }
}
#EndRegion './Public/New-xDscDiagnosticsZip.ps1' 199
#Region './Public/Trace-xDscOperation.ps1' 0
<#
.SYNOPSIS
Traces through any DSC operation selected from among all operations using its unique sequence ID (obtained from Get-xDscOperation), or from its unique Job ID

.DESCRIPTION
This function, when called, will look through all the event logs for DSC, and output the results in the form of an object, that contains the event type, event message, time created, computer name, job id, sequence number, and the event information.

.PARAMETER SequenceId
Each operation in DSC has a certain Sequence ID, ordered by time of creation of these DSC operations. The sequence IDs can be obtained by running Get-xDscOperation
By mentioning a sequence ID, the trace of the corresponding DSC operation is output.

.PARAMETER JobId
The event viewer shows each DSC event start with a unique job ID for each operation. If this job id is specified with this parameter, then all diagnostic messages displayed are taken from the dsc operation pertaining to this job id.

.PARAMETER ComputerName
The names of computers in which you would like to trace the past DSC operations

.PARAMETER Credential
The credential needed to access the computers specified inside ComputerName parameters

.EXAMPLE
Trace-xDscOperation
To Obtain the diagnostic information for the latest operation

.EXAMPLE
Trace-xDscOperation -sequenceId 3
To obtain the diagnostic information for the third latest operation

.EXAMPLE
Trace-xDscOperation -JobId 11112222-1111-1122-1122-111122221111
To diagnose an operation with job Id 11112222-1111-1122-1122-111122221111

.EXAMPLE
Trace-xDscOperation -ComputerName XYZ -sequenceID 2
To Get Logs from a remote computer

.EXAMPLE
Trace-xDscOperation -Computername XYZ -Credential $mycredential -sequenceID 2

To Get logs from a remote computer with credentials

.EXAMPLE
Trace-xDscOperation -ComputerName @("PN25113D0891", "PN25113D0890")

To get logs from multiple remote computers

.NOTES
Please note that to perform actions on the remote computer, have the firewall for remote configuration enabled. This can be done with the following command:

New-NetFirewallRule -Name "Service RemoteAdmin" -Action Allow
#>
function Trace-xDscOperation
{
    [cmdletBinding()]
    param
    (
        [UInt32]$SequenceID = 1, #latest is by default
        [Guid]$JobId,
        [String[]]$ComputerName,
        [pscredential]$Credential
    )

    Add-ClassTypes

    if ($ComputerName)
    {
        $script:UsingComputerName = $true
        $args = $PSBoundParameters
        $null = $args.Remove("ComputerName")
        $null = $args.Remove("Credential")

        foreach ($thisComputerName in $ComputerName)
        {
            LogDscDiagnostics -Verbose "Gathering logs for Computer $thisComputerName ..."
            $script:ThisComputerName = $thisComputerName
            $script:ThisCredential = $Credential
            Trace-DscOperationInternal  @PSBoundParameters
        }
    }
    else
    {
        $script:ThisComputerName = $env:COMPUTERNAME
        Trace-DscOperationInternal @PSBoundParameters
        $script:UsingComputerName = $false
    }
}
#EndRegion './Public/Trace-xDscOperation.ps1' 86
#Region './Public/Unprotect-xDscConfiguration.ps1' 0
# decrypt one of the lcm mof
function Unprotect-xDscConfiguration
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateSet('Current', 'Pending', 'Previous')]
        $Stage
    )

    Add-Type -AssemblyName System.Security

    $path = "$env:windir\System32\Configuration\$stage.mof"

    if (Test-Path $path)
    {
        $secureString = Get-Content $path -Raw

        $enc = [system.Text.Encoding]::Default

        $data = $enc.GetBytes($secureString)

        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect( $data, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine )

        $enc = [system.text.encoding]::Unicode

        $enc.GetString($bytes)
    }
    else
    {
        throw (New-Object -TypeName 'System.IO.FileNotFoundException' -ArgumentList @("The stage $stage was not found"))
    }
}
#EndRegion './Public/Unprotect-xDscConfiguration.ps1' 34
#Region './Public/Update-xDscEventLogStatus.ps1' 0
<#
.SYNOPSIS
Sets any DSC Event log (Operational, analytic, debug )

.DESCRIPTION
This cmdlet will set a DSC log when run with Update-xDscEventLogStatus <channel Name>.

.PARAMETER Channel
Mandatory parameter : Name of the channel of the event log to be set - It has to be one of Operational, Analytic or debug

.PARAMETER Status
Mandatory Parameter : This is a string parameter which is either "Enabled" or "disabled" representing the required final status of the log channel. If this value is "enabled", then the channel is enabled.

.PARAMETER ComputerName
String parameter that can be used to set the event log channel on a remote computer . Note : It may need a credential

.PARAMETER Credential
Credential to be passed in so that the operation can be performed on the remote computer

.EXAMPLE
C:\PS> Update-xDscEventLogStatus "Analytic" -Status "Enabled"

.EXAMPLE
C:\PS> Update-xDscEventLogStatus -Channel "Debug" -ComputerName "ABC"

.EXAMPLE
C:\PS> Update-xDscEventLogStatus -Channel "Debug" -ComputerName "ABC" -Status Disabled

#>
function Update-xDscEventLogStatus
{
    [cmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateSet('Analytic' , 'Debug' , 'Operational')]
        [String]$Channel,

        [Parameter(Mandatory)]
        [ValidateSet('Enabled' , 'Disabled')]
        [String]$Status,

        [String]$ComputerName,

        [PSCredential]$Credential
    )

    $LogName = "Microsoft-Windows-Dsc"
    $statusEnabled = $false
    $eventLogFullName = "$LogName/$Channel"
    if ($Status -eq "Enabled")
    {
        $statusEnabled = $true
    }
    #Form the basic command which will enable/disable any event log
    $commandToExecute = "wevtutil set-log $eventLogFullName /e:$statusEnabled /q:$statusEnabled   "

    LogDscDiagnostics -Verbose "Changing status of the log $eventLogFullName to $Status"
    #If there is no computer name specified, just invoke the command in the same computer
    if (!$ComputerName)
    {
        Invoke-Expression $commandToExecute
    }
    else
    {
        #For any other computer, invoke command.
        $scriptToSetChannel = [Scriptblock]::Create($commandToExecute)

        if ($Credential)
        {
            Invoke-Command -ScriptBlock $scriptToSetChannel -ComputerName $ComputerName  -Credential $Credential
        }
        else
        {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptToSetChannel
        }
    }

    LogDscDiagnostics -Verbose "The $Channel event log has been $Status. "
}
#EndRegion './Public/Update-xDscEventLogStatus.ps1' 80
