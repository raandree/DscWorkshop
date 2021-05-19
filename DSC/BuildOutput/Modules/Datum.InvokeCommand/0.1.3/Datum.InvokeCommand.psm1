#Region '.\Prefix.ps1' 0
$here = $PSScriptRoot
$modulePath = Join-Path -Path $here -ChildPath 'Modules'

Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'DscResource.Common')

$script:localizedData = Get-LocalizedData -DefaultUICulture en-US
#EndRegion '.\Prefix.ps1' 7
#Region '.\Private\Get-DatumCurrentNode.ps1' 0
function Get-DatumCurrentNode
{
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $fileNode = $File | Get-Content | ConvertFrom-Yaml
    $rsopNode = Get-DatumRsop -Datum $datum -AllNodes $currentNode

    if ($rsopNode)
    {
        $rsopNode
    }
    else
    {
        $fileNode
    }
}
#EndRegion '.\Private\Get-DatumCurrentNode.ps1' 20
#Region '.\Private\Get-RelativeFileName.ps1' 0
function Get-RelativeFileName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path
    )

    if (-not $Path)
    {
        return [string]::Empty
    }
    
    try
    {
        $p = Resolve-Path -Path $Path -Relative -ErrorAction Stop
        $p = $p -split '\\'
        $p[-1] = [System.IO.Path]::GetFileNameWithoutExtension($p[-1])
        $p[2..($p.Length - 1)] -join '\'
    }
    catch { }
}
#EndRegion '.\Private\Get-RelativeFileName.ps1' 24
#Region '.\Private\Invoke-InvokeCommandActionInternal.ps1' 0
function Invoke-InvokeCommandActionInternal
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateSet('ExpandableString', 'HereString', 'ScriptBlock')]
        [string]$DatumType
    )

    if (-not $datum -and -not $DatumTree)
    {
        return $InputObject
    }
    elseif (-not $datum -and $DatumTree)
    {
        $datum = $DatumTree
    }

    #Prevent self-referencing loop
    if (($InputObject.Contains('Get-DatumRsop')) -and ((Get-PSCallStack).Command | Where-Object { $_ -eq 'Get-DatumRsop' }).Count -gt 1)
    {
        return $InputObject
    }

    try
    {
        $callId = New-Guid
        $start = Get-Date
        Write-Verbose "Invoking command '$InputObject'. CallId is '$callId'"
        $command = [scriptblock]::Create($InputObject)
        $result = if ($DatumType -eq 'ScriptBlock')
        {
            & (& $command)
        }
        else
        {
            & $command
        }

        $dynamicPart = $true
        while ($dynamicPart)
        {
            if ($dynamicPart = Test-InvokeCommandFilter -InputObject $result -ReturnValue)
            {
                $innerResult = Invoke-InvokeCommandAction -InputObject $result -Node $node
                $result = $result.Replace($dynamicPart, $innerResult)
            }
        }
        $duration = (Get-Date) - $start
        Write-Verbose "Invoke with CallId '$callId' has taken $([System.Math]::Round($duration.TotalSeconds, 2)) seconds"

        if ($result -is [string])
        {
            $ExecutionContext.InvokeCommand.ExpandString($result)
        }
        else
        {
            $result
        }
    }
    catch
    {
        Write-Error -Message ($script:localizedData.CannotCreateScriptBlock -f $InputObject, $_.Exception.Message) -Exception $_.Exception
        return $InputObject
    }
}
#EndRegion '.\Private\Invoke-InvokeCommandActionInternal.ps1' 69
#Region '.\Public\Invoke-InvokeCommandAction.ps1' 0
function Invoke-InvokeCommandAction
{
    <#
    .SYNOPSIS
    Call the scriptblock that is given via Datum.

    .DESCRIPTION
    When Datum uses this handler to invoke whatever script block is given to it. The returned
    data is used as configuration data.

    .PARAMETER InputObject
    Script block to invoke

    .PARAMETER Header
    Header of the Datum data string that encapsulates the script block.
    The default is [Command= but can be customized (i.e. in the Datum.yml configuration file)

    .PARAMETER Footer
    Footer of the Datum data string that encapsulates the encrypted data. The default is ]

    .EXAMPLE
    $command | Invoke-ProtectedDatumAction

    .NOTES
    The arguments you can set in the Datum.yml is directly related to the arguments of this function.

    #>
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [object]
        $InputObject,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [object]
        $Node
    )

    if ($result = ($datumInvokeCommandRegEx.Match($InputObject).Groups['Content'].Value))
    {
        if ($datumType = 
            & {
                $errors = $null
                $tokens = $null

                $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                    $result,
                    [ref]$tokens,
                    [ref]$errors
                )

                if (($tokens[0].Kind -eq 'LCurly' -and $tokens[-2].Kind -eq 'RCurly' -and $tokens[-1].Kind -eq 'EndOfInput') -or
                    ($tokens[0].Kind -eq 'LCurly' -and $tokens[-3].Kind -eq 'RCurly' -and $tokens[-2].Kind -eq 'NewLine' -and $tokens[-1].Kind -eq 'EndOfInput'))
                {
                    'ScriptBlock'
                }
                elseif ($tokens |
                        & {
                            process
                            {
                                if ($_.Kind -eq 'StringExpandable')
                                {
                                    $_
                                }
                            }
                        })
                {
                    'ExpandableString'
                }
                elseif (
                    $tokens |
                        & {
                            process
                            {
                                if ($_.Kind -eq 'HereStringExpandable')
                                {
                                    $_
                                }
                            }
                        }
                )
                {
                    'HereString'
                }
                else
                {
                    $false
                }
            })
        {
            try
            {
                $file = Get-Item -Path $InputObject.__File -ErrorAction Ignore
            }
            catch
            {
            }

            if (-not $Node -and $file)
            {
                if ($file.Name -ne 'Datum.yml')
                {
                    $Node = Get-DatumCurrentNode -File $file

                    if (-not $Node)
                    {
                        return $InputObject
                    }
                }
            }

            try
            {
                Invoke-InvokeCommandActionInternal -InputObject $result -DatumType $datumType -ErrorAction Stop
            }
            catch
            {
                Write-Warning ($script:localizedData.ErrorCallingInvokeInvokeCommandActionInternal -f $_.Exception.Message, $result)
            }
        }
        else
        {
            $InputObject
        }
    }
    else
    {
        $InputObject
    }
}
#EndRegion '.\Public\Invoke-InvokeCommandAction.ps1' 116
#Region '.\Public\Test-InvokeCommandFilter.ps1' 0
function Test-InvokeCommandFilter
{
    <#
    .SYNOPSIS
    Filter function to verify if it's worth triggering the action for the data block.

    .DESCRIPTION
    This function is run in the ConvertTo-Datum function of the Datum module on every pass,
    and when it returns true, the action of the handler is called.

    .PARAMETER InputObject
    Object to test to decide whether to trigger the action or not

    .EXAMPLE
    $object | Test-ProtectedDatumFilter

    #>
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [switch]
        $ReturnValue
    )

    if ($InputObject -is [string])
    {
        $all = $datumInvokeCommandRegEx.Match($InputObject.Trim()).Groups['0'].Value
        $content = $datumInvokeCommandRegEx.Match($InputObject.Trim()).Groups['Content'].Value

        if ($ReturnValue -and $content)
        {
            $all
        }
        elseif ($content)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
    else
    {
        return $false
    }
}
#EndRegion '.\Public\Test-InvokeCommandFilter.ps1' 51

