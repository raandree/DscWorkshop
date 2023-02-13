#Region './prefix.ps1' 0
#Requires -Version 4.0

$script:diagnosticRecordType = [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]
$script:diagnosticRecord = @{
    Message  = ''
    Extent   = $null
    RuleName = $null
    Severity = 'Warning'
}
#EndRegion './prefix.ps1' 9
#Region './Private/Get-LocalizedData.ps1' 0
<#
.SYNOPSIS
Gets language-specific data into scripts and functions based on the UI culture
that is selected for the operating system.
Similar to Import-LocalizedData, with extra parameter 'DefaultUICulture'.

.DESCRIPTION
The Get-LocalizedData cmdlet dynamically retrieves strings from a subdirectory
whose name matches the UI language set for the current user of the operating system.
It is designed to enable scripts to display user messages in the UI language selected
by the current user.

Get-LocalizedData imports data from .psd1 files in language-specific subdirectories
of the script directory and saves them in a local variable that is specified in the
command. The cmdlet selects the subdirectory and file based on the value of the
$PSUICulture automatic variable. When you use the local variable in the script to
display a user message, the message appears in the user's UI language.

You can use the parameters of G-LocalizedData to specify an alternate UI culture,
path, and file name, to add supported commands, and to suppress the error message that
appears if the .psd1 files are not found.

The G-LocalizedData cmdlet supports the script internationalization
initiative that was introduced in Windows PowerShell 2.0. This initiative
aims to better serve users worldwide by making it easy for scripts to display
user messages in the UI language of the current user. For more information
about this and about the format of the .psd1 files, see about_Script_Internationalization.

.PARAMETER BindingVariable
Specifies the variable into which the text strings are imported. Enter a variable
name without a dollar sign ($).

In Windows PowerShell 2.0, this parameter is required. In Windows PowerShell 3.0,
this parameter is optional. If you omit this parameter, Import-LocalizedData
returns a hash table of the text strings. The hash table is passed down the pipeline
or displayed at the command line.

When using Import-LocalizedData to replace default text strings specified in the
DATA section of a script, assign the DATA section to a variable and enter the name
of the DATA section variable in the value of the BindingVariable parameter. Then,
when Import-LocalizedData saves the imported content in the BindingVariable, the
imported data will replace the default text strings. If you are not specifying
default text strings, you can select any variable name.
.PARAMETER UICulture
Specifies an alternate UI culture. The default is the value of the $PsUICulture
automatic variable. Enter a UI culture in <language>-<region> format, such as
en-US, de-DE, or ar-SA.

The value of the UICulture parameter determines the language-specific subdirectory
(within the base directory) from which Import-LocalizedData gets the .psd1 file
for the script.

The cmdlet searches for a subdirectory with the same name as the value of the
UICulture parameter or the $PsUICulture automatic variable, such as de-DE or
ar-SA. If it cannot find the directory, or the directory does not contain a .psd1
file for the script, it searches for a subdirectory with the name of the language
code, such as de or ar. If it cannot find the subdirectory or .psd1 file, the
command fails and the data is displayed in the default language specified in the
script.

.PARAMETER BaseDirectory
Specifies the base directory where the .psd1 files are located. The default is
the directory where the script is located. Import-LocalizedData searches for
the .psd1 file for the script in a language-specific subdirectory of the base
directory.

.PARAMETER FileName
Specifies the name of the data file (.psd1) to be imported. Enter a file name.
You can specify a file name that does not include its .psd1 file name extension,
or you can specify the file name including the .psd1 file name extension.

The FileName parameter is required when Import-LocalizedData is not used in a
script. Otherwise, the parameter is optional and the default value is the base
name of the script. You can use this parameter to direct Import-LocalizedData
to search for a different .psd1 file.

For example, if the FileName is omitted and the script name is FindFiles.ps1,
Import-LocalizedData searches for the FindFiles.psd1 data file.

.PARAMETER SupportedCommand
Specifies cmdlets and functions that generate only data.

Use this parameter to include cmdlets and functions that you have written or
tested. For more information, see about_Script_Internationalization.

.PARAMETER DefaultUICulture
Specifies which UICulture to default to if current UI culture or its parents
culture don't have matching data file.

For example, if you have a data file in 'en-US' but not in 'en' or 'en-GB' and
your current culture is 'en-GB', you can default back to 'en-US'.

.NOTES
Before using Import-LocalizedData, localize your user messages. Format the messages
for each locale (UI culture) in a hash table of key/value pairs, and save the
hash table in a file with the same name as the script and a .psd1 file name extension.
Create a directory under the script directory for each supported UI culture, and
then save the .psd1 file for each UI culture in the directory with the UI
culture name.

For example, localize your user messages for the de-DE locale and format them in
a hash table. Save the hash table in a <ScriptName>.psd1 file. Then create a de-DE
subdirectory under the script directory, and save the de-DE <ScriptName>.psd1
file in the de-DE subdirectory. Repeat this method for each locale that you support.

Import-LocalizedData performs a structured search for the localized user
messages for a script.

Import-LocalizedData begins the search in the directory where the script file
is located (or the value of the BaseDirectory parameter). It then searches within
the base directory for a subdirectory with the same name as the value of the
$PsUICulture variable (or the value of the UICulture parameter), such as de-DE or
ar-SA. Then, it searches in that subdirectory for a .psd1 file with the same name
as the script (or the value of the FileName parameter).

If Import-LocalizedData cannot find a subdirectory with the name of the UI culture,
or the subdirectory does not contain a .psd1 file for the script, it searches for
a .psd1 file for the script in a subdirectory with the name of the language code,
such as de or ar. If it cannot find the subdirectory or .psd1 file, the command
fails, the data is displayed in the default language in the script, and an error
message is displayed explaining that the data could not be imported. To suppress
the message and fail gracefully, use the ErrorAction common parameter with a value
of SilentlyContinue.

If Import-LocalizedData finds the subdirectory and the .psd1 file, it imports the
hash table of user messages into the value of the BindingVariable parameter in the
command. Then, when you display a message from the hash table in the variable, the
localized message is displayed.

For more information, see about_Script_Internationalization.
#>
function Get-LocalizedData
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [Alias('Variable')]
        [ValidateNotNullOrEmpty()]
        [string]
        ${BindingVariable},

        [Parameter(Position = 1, ParameterSetName = 'TargetedUICulture')]
        [string]
        ${UICulture},

        [Parameter()]
        [string]
        ${BaseDirectory},

        [Parameter()]
        [string]
        ${FileName},

        [Parameter()]
        [string[]]
        ${SupportedCommand},

        [Parameter(Position = 1, ParameterSetName = 'DefaultUICulture')]
        [string]
        ${DefaultUICulture}
    )

    begin
    {
        # Because Proxy Command changes the Invocation origin, we need to be explicit
        # when handing the pipeline back to original command
        if (!$PSBoundParameters.ContainsKey('FileName'))
        {
            if ($myInvocation.ScriptName)
            {
                $file = ([io.FileInfo]$myInvocation.ScriptName)
            }
            else
            {
                $file = [io.FileInfo]$myInvocation.MyCommand.Module.Path
            }
            $FileName = $file.BaseName
            $PSBoundParameters.add('FileName', $file.Name)
        }

        if ($PSBoundParameters.ContainsKey('BaseDirectory'))
        {
            $CallingScriptRoot = $BaseDirectory
        }
        else
        {
            $CallingScriptRoot = $myInvocation.PSScriptRoot
            $PSBoundParameters.add('BaseDirectory', $CallingScriptRoot)
        }

        if ($PSBoundParameters.ContainsKey('DefaultUICulture') -and !$PSBoundParameters.ContainsKey('UICulture'))
        {
            # We don't want the resolution to eventually return the ModuleManifest
            # So we run the same GetFilePath() logic than here:
            # https://github.com/PowerShell/PowerShell/blob/master/src/Microsoft.PowerShell.Commands.Utility/commands/utility/Import-LocalizedData.cs#L302-L333
            # and if we see it will return the wrong thing, set the UICulture to DefaultUI culture, and return the logic to Import-LocalizedData
            $currentCulture = Get-UICulture

            $fullFileName = $FileName + ".psd1"
            $LanguageFile = $null

            while ($null -ne $currentCulture -and $currentCulture.Name -and !$LanguageFile)
            {
                $filePath = [io.Path]::Combine($CallingScriptRoot, $CurrentCulture.Name, $fullFileName)
                if (Test-Path $filePath)
                {
                    Write-Debug "Found $filePath"
                    $LanguageFile = $filePath
                }
                else
                {
                    Write-Debug "File $filePath not found"
                }
                $currentCulture = $currentCulture.Parent
            }

            if (!$LanguageFile)
            {
                $PSBoundParameters.Add('UICulture', $DefaultUICulture)
            }
            $null = $PSBoundParameters.remove('DefaultUICulture')
        }

        try
        {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Utility\Import-LocalizedData', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = { & $wrappedCmd @PSBoundParameters }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
            $steppablePipeline.Begin($PSCmdlet)
        }
        catch
        {
            throw
        }
    }

    process
    {
        try
        {
            $steppablePipeline.Process($_)
        }
        catch
        {
            throw
        }
    }

    end
    {
        if ($BindingVariable -and ($valueToBind = Get-Variable -Name $BindingVariable -ValueOnly -ErrorAction Ignore))
        {
            # Bringing the variable to the parent scope
            Set-Variable -Scope 1 -Name $BindingVariable -Force -ErrorAction SilentlyContinue -Value $valueToBind
        }
        try
        {
            $steppablePipeline.End()
        }
        catch
        {
            throw
        }
    }
}
#EndRegion './Private/Get-LocalizedData.ps1' 272
#Region './Private/Get-StatementBlockAsRow.ps1' 0
<#
    .SYNOPSIS
        Helper function for the Test-Statement* helper functions.
        Returns the extent text as an array of strings.

    .EXAMPLE
        Get-StatementBlockAsRow -StatementBlock $ScriptBlockAst.Extent

    .INPUTS
        [System.String]

    .OUTPUTS
        [System.String[]]

   .NOTES
        None
#>
function Get-StatementBlockAsRow
{
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StatementBlock
    )

    <#
        Remove carriage return since the file is different depending if it's run in
        AppVeyor or locally. Locally it contains both '\r\n', but when cloned in
        AppVeyor it only contains '\n'.
    #>
    $statementBlockWithNewLine = $StatementBlock -replace '\r', ''
    return $statementBlockWithNewLine -split '\n'
}
#EndRegion './Private/Get-StatementBlockAsRow.ps1' 37
#Region './Private/New-SuggestedCorrection.ps1' 0
<#
    .SYNOPSIS
        Creates a suggested correction
    .PARAMETER Extent
        The extent that needs correction
    .PARAMETER NewString
        The string that should replace the extent
    .PARAMETER Description
        The description that should be shown
    .OUTPUTS
        Output (if any)
#>
function New-SuggestedCorrection
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.CorrectionExtent])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.IScriptExtent]
        $Extent,

        [Parameter()]
        [System.String]
        $NewString,

        [Parameter()]
        [System.String]
        $Description
    )

    if ($PSCmdlet.ShouldProcess("Create correction extent"))
    {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.CorrectionExtent]::new(
            $Extent.StartLineNumber,
            $Extent.EndLineNumber,
            $Extent.StartColumnNumber,
            $Extent.EndColumnNumber,
            $NewString,
            $Extent.File,
            $Description
        )
    }
}
#EndRegion './Private/New-SuggestedCorrection.ps1' 43
#Region './Private/Test-IsInClass.ps1' 0
<#
    .SYNOPSIS
        Helper function to check if an Ast is part of a class.
        Returns true or false

    .EXAMPLE
        Test-IsInClass -Ast $ParameterBlockAst

    .INPUTS
        [System.Management.Automation.Language.Ast]

    .OUTPUTS
        [System.Boolean]

   .NOTES
        I initially just walked up the AST tree till I hit
        a TypeDefinitionAst that was a class

        But...

        That means it would throw false positives for things like

        class HasAFunctionInIt
        {
            [Func[int,int]] $MyFunc = {
                param
                (
                    [Parameter(Mandatory=$true)]
                    [int]
                    $Input
                )

                $Input
            }
        }

        Where the param block and all its respective items ARE
        valid being in their own anonymous function definition
        that just happens to be inside a class property's
        assignment value

        So This check has to be a DELIBERATE step by step up the
        AST Tree ONLY far enough to validate if it is directly
        part of a class or not
#>
function Test-IsInClass
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.Ast]
        $Ast
    )

    [System.Boolean] $inAClass = $false
    # Is a Named Attribute part of Class Property?
    if ($Ast -is [System.Management.Automation.Language.NamedAttributeArgumentAst])
    {
        # Parent is an Attribute Ast AND
        $inAClass = $Ast.Parent -is [System.Management.Automation.Language.AttributeAst] -and
        # Grandparent is a Property Member Ast (This Ast Type ONLY shows up inside a TypeDefinitionAst) AND
        $Ast.Parent.Parent -is [System.Management.Automation.Language.PropertyMemberAst] -and
        # Great Grandparent is a Type Definition Ast AND
        $Ast.Parent.Parent.Parent -is [System.Management.Automation.Language.TypeDefinitionAst] -and
        # Great Grandparent is a Class
        $ast.Parent.Parent.Parent.IsClass
    }
    # Is a Parameter part of a Class Method?
    elseif ($Ast -is [System.Management.Automation.Language.ParameterAst])
    {
        # Parent is a Function Definition Ast AND
        $inAClass = $Ast.Parent -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        # Grandparent is a Function Member Ast (This Ast Type ONLY shows up inside a TypeDefinitionAst) AND
        $Ast.Parent.Parent -is [System.Management.Automation.Language.FunctionMemberAst] -and
        # Great Grandparent is a Type Definition Ast AND
        $Ast.Parent.Parent.Parent -is [System.Management.Automation.Language.TypeDefinitionAst] -and
        # Great Grandparent is a Class
        $Ast.Parent.Parent.Parent.IsClass
    }

    $inAClass
}
#EndRegion './Private/Test-IsInClass.ps1' 85
#Region './Private/Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine.ps1' 0

<#
    .SYNOPSIS
        Helper function for the Measure-*Statement PSScriptAnalyzer rules.
        Test a single statement block for only one new line after opening brace.

    .EXAMPLE
        Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine -StatementBlock $ScriptBlockAst.Extent

    .INPUTS
        [System.String]

    .OUTPUTS
        [System.Boolean]

   .NOTES
        None
#>
function Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StatementBlock
    )

    $statementBlockRows = Get-StatementBlockAsRow -StatementBlock $StatementBlock
    if ($statementBlockRows.Count -ge 3)
    {
        # Check so that an opening brace is followed by only one new line.
        if (-not $statementBlockRows[2].Trim())
        {
            return $true
        } # if
    } # if

    return $false
}
#EndRegion './Private/Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine.ps1' 42
#Region './Private/Test-StatementOpeningBraceIsNotFollowedByNewLine.ps1' 0

<#
    .SYNOPSIS
        Helper function for the Measure-*Statement PSScriptAnalyzer rules.
        Test a single statement block for new line after opening brace.

    .EXAMPLE
        Test-StatementOpeningBraceIsNotFollowedByNewLine -StatementBlock $ScriptBlockAst.Extent

    .INPUTS
        [System.String]

    .OUTPUTS
        [System.Boolean]

   .NOTES
        None
#>
function Test-StatementOpeningBraceIsNotFollowedByNewLine
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StatementBlock
    )

    $statementBlockRows = Get-StatementBlockAsRow -StatementBlock $StatementBlock
    if ($statementBlockRows.Count -ge 2)
    {
        # Check so that an opening brace is followed by a new line.
        if ($statementBlockRows[1] -match '\{.+')
        {
            return $true
        } # if
    } # if

    return $false
}
#EndRegion './Private/Test-StatementOpeningBraceIsNotFollowedByNewLine.ps1' 42
#Region './Private/Test-StatementOpeningBraceOnSameLine.ps1' 0

<#
    .SYNOPSIS
        Helper function for the Measure-*Statement PSScriptAnalyzer rules.
        Test a single statement block for opening brace on the same line.

    .EXAMPLE
        Test-StatementOpeningBraceOnSameLine -StatementBlock $ScriptBlockAst.Extent

    .INPUTS
        [System.String]

    .OUTPUTS
        [System.Boolean]

   .NOTES
        None
#>
function Test-StatementOpeningBraceOnSameLine
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StatementBlock
    )

    $statementBlockRows = Get-StatementBlockAsRow -StatementBlock $StatementBlock
    if ($statementBlockRows.Count)
    {
        # Check so that an opening brace does not exist on the same line as the statement.
        if ($statementBlockRows[0] -match '{[\s]*$')
        {
            return $true
        } # if
    } # if

    return $false
}
#EndRegion './Private/Test-StatementOpeningBraceOnSameLine.ps1' 42
#Region './Public/Measure-CatchClause.ps1' 0
<#
    .SYNOPSIS
        Validates the catch-clause block braces and new lines around braces.

    .DESCRIPTION
        Each catch-clause should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .PARAMETER CatchClauseAst
        AST Block used to evaluate the rule

    .EXAMPLE
        Measure-CatchClause -CatchClauseAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.CatchClauseAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-CatchClause
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.CatchClauseAst]
        $CatchClauseAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $CatchClauseAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $CatchClauseAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.CatchClauseOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        }

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.CatchClauseOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.CatchClauseOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-CatchClause.ps1' 67
#Region './Public/Measure-DoUntilStatement.ps1' 0
<#
    .SYNOPSIS
        Validates the DoUntil-statement block braces and new lines around braces.

    .DESCRIPTION
        Each DoUntil-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-DoUntilStatement -DoUntilStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.DoUntilStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-DoUntilStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.DoUntilStatementAst]
        $DoUntilStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $DoUntilStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $DoUntilStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.DoUntilStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.DoUntilStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.DoUntilStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-DoUntilStatement.ps1' 64
#Region './Public/Measure-DoWhileStatement.ps1' 0

<#
    .SYNOPSIS
        Validates the DoWhile-statement block braces and new lines around braces.

    .DESCRIPTION
        Each DoWhile-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-DoWhileStatement -DoWhileStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.DoWhileStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-DoWhileStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.DoWhileStatementAst]
        $DoWhileStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $DoWhileStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $DoWhileStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.DoWhileStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.DoWhileStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.DoWhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-DoWhileStatement.ps1' 65
#Region './Public/Measure-ForEachStatement.ps1' 0

<#
    .SYNOPSIS
        Validates the foreach-statement block braces and new lines around braces.

    .DESCRIPTION
        Each foreach-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-ForEachStatement -ForEachStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.ForEachStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-ForEachStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ForEachStatementAst]
        $ForEachStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $ForEachStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $ForEachStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.ForEachStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.ForEachStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.ForEachStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-ForEachStatement.ps1' 65
#Region './Public/Measure-ForStatement.ps1' 0

<#
    .SYNOPSIS
        Validates the for-statement block braces and new lines around braces.

    .DESCRIPTION
        Each for-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-ForStatement -ForStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.ForStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-ForStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ForStatementAst]
        $ForStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $ForStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $ForStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.ForStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.ForStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.ForStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-ForStatement.ps1' 65
#Region './Public/Measure-FunctionBlockBrace.ps1' 0

<#
    .SYNOPSIS
        Validates the function block braces and new lines around braces.

    .DESCRIPTION
        Each function should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-FunctionBlockBrace -FunctionDefinitionAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.FunctionDefinitionAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-FunctionBlockBrace
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.FunctionDefinitionAst]
        $FunctionDefinitionAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $FunctionDefinitionAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $FunctionDefinitionAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.FunctionOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.FunctionOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.FunctionOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-FunctionBlockBrace.ps1' 65
#Region './Public/Measure-Hashtable.ps1' 0
<#
    .SYNOPSIS
        Validates all hashtables.

    .DESCRIPTION
        Hashtables should have the correct format

    .EXAMPLE
        PS C:\> Measure-Hashtable -HashtableAst $HashtableAst

    .INPUTS
        [System.Management.Automation.Language.HashtableAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

    .NOTES
        None
#>
function Measure-Hashtable
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.HashtableAst[]]
        $HashtableAst
    )

    try
    {
        foreach ($hashtable in $HashtableAst)
        {
            # Empty hashtables should be ignored
            if ($hashtable.extent.Text -eq '@{}' -or $hashtable.extent.Text -eq '@{ }')
            {
                continue
            }

            $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

            $hashtableLines = $hashtable.Extent.Text -split '\n'

            # Hashtable should start with '@{' and end with '}'
            if (($hashtableLines[0] -notmatch '\s*@?{\r' -and $hashtableLines[0] -notmatch '\s*@?{$') -or
                $hashtableLines[-1] -notmatch '\s*}')
            {
                $script:diagnosticRecord['Extent'] = $hashtable.Extent
                $script:diagnosticRecord['Message'] = $localizedData.HashtableShouldHaveCorrectFormat
                $script:diagnosticRecord -as $diagnosticRecordType
            }
            else
            {
                # We alredy checked that the first line is correctly formatted. Getting the starting indentation here
                $initialIndent = ([regex]::Match($hashtable.Extent.StartScriptPosition.Line, '(\s*)')).Length
                $expectedLineIndent = $initialIndent + 5

                foreach ($keyValuePair in $hashtable.KeyValuePairs)
                {
                    if ($keyValuePair.Item1.Extent.StartColumnNumber -ne $expectedLineIndent)
                    {
                        $script:diagnosticRecord['Extent'] = $hashtable.Extent
                        $script:diagnosticRecord['Message'] = $localizedData.HashtableShouldHaveCorrectFormat
                        $script:diagnosticRecord -as $diagnosticRecordType
                        break
                    }
                }
            }
        }
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-Hashtable.ps1' 76
#Region './Public/Measure-IfStatement.ps1' 0

<#
    .SYNOPSIS
        Validates the if-statement block braces and new lines around braces.

    .DESCRIPTION
        Each if-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-IfStatement -IfStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.IfStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-IfStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.IfStatementAst]
        $IfStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $IfStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $IfStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.IfStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.IfStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.IfStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-IfStatement.ps1' 65
#Region './Public/Measure-Keyword.ps1' 0
<#
    .SYNOPSIS
        Validates all keywords.

    .DESCRIPTION
        Each keyword should be in all lower case.

    .EXAMPLE
        Measure-Keyword -Token $Token

    .INPUTS
        [System.Management.Automation.Language.Token[]]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-Keyword
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.Token[]]
        $Token
    )

    try
    {
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $keywordsToIgnore = @('configuration')
        $keywordFlag = [System.Management.Automation.Language.TokenFlags]::Keyword
        $keywords = $Token.Where{ $_.TokenFlags.HasFlag($keywordFlag) -and
            $_.Kind -ne 'DynamicKeyword' -and
            $keywordsToIgnore -notContains $_.Text
        }
        $upperCaseTokens = $keywords.Where{ $_.Text -cMatch '[A-Z]+' }

        $tokenWithNoSpace = $keywords.Where{ $_.Extent.StartScriptPosition.Line -match "$($_.Extent.Text)\(.*" }

        foreach ($item in $upperCaseTokens)
        {
            $script:diagnosticRecord['Extent'] = $item.Extent
            $script:diagnosticRecord['Message'] = $localizedData.StatementsContainsUpperCaseLetter -f $item.Text
            $suggestedCorrections = New-Object -TypeName Collections.Generic.List[Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.CorrectionExtent]
            $splat = @{
                Extent      = $item.Extent
                NewString   = $item.Text.ToLower()
                Description = ('Replace {0} with {1}' -f ($item.Extent.Text, $item.Extent.Text.ToLower()))
            }
            $suggestedCorrections.Add((New-SuggestedCorrection @splat)) | Out-Null
            $suggestedCorrections.Add($suggestedCorrection) | Out-Null

            $script:diagnosticRecord['suggestedCorrections'] = $suggestedCorrections
            $script:diagnosticRecord -as $diagnosticRecordType
        }

        foreach ($item in $tokenWithNoSpace)
        {
            $script:diagnosticRecord['Extent'] = $item.Extent
            $script:diagnosticRecord['Message'] = $localizedData.OneSpaceBetweenKeywordAndParenthesis
            $suggestedCorrections = New-Object -TypeName Collections.Generic.List[Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.CorrectionExtent]
            $splat = @{
                Extent      = $item.Extent
                NewString   = "$($item.Text) "
                Description = ('Replace {0} with {1}' -f ("$($item.Extent.Text)(", "$($item.Text) ("))
            }
            $suggestedCorrections.Add((New-SuggestedCorrection @splat)) | Out-Null

            $script:diagnosticRecord['suggestedCorrections'] = $suggestedCorrections
            $script:diagnosticRecord -as $diagnosticRecordType
        }
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-Keyword.ps1' 83
#Region './Public/Measure-ParameterBlockMandatoryNamedArgument.ps1' 0
<#
    .SYNOPSIS
        Validates use of the Mandatory named argument within a Parameter attribute.

    .DESCRIPTION
        If a parameter attribute contains the mandatory attribute the
        mandatory attribute must be formatted correctly.

    .EXAMPLE
        Measure-ParameterBlockMandatoryNamedArgument -NamedAttributeArgumentAst $namedAttributeArgumentAst

    .INPUTS
        [System.Management.Automation.Language.NamedAttributeArgumentAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

    .NOTES
        None
#>
function Measure-ParameterBlockMandatoryNamedArgument
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.NamedAttributeArgumentAst]
        $NamedAttributeArgumentAst
    )

    try
    {
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName
        [System.Boolean] $inAClass = Test-IsInClass -Ast $NamedAttributeArgumentAst

        <#
            Parameter Attributes are not valid in classes, and DscProperty does
            not use the (Mandatory = $true) format just DscProperty(Mandatory)
        #>
        if (!$inAClass)
        {
            if ($NamedAttributeArgumentAst.ArgumentName -eq 'Mandatory')
            {
                $script:diagnosticRecord['Extent'] = $NamedAttributeArgumentAst.Extent

                if ($NamedAttributeArgumentAst)
                {
                    $invalidFormat = $false
                    try
                    {
                        $value = $NamedAttributeArgumentAst.Argument.SafeGetValue()
                        if ($value -eq $false)
                        {
                            $script:diagnosticRecord['Message'] = $localizedData.ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat

                            $script:diagnosticRecord -as $script:diagnosticRecordType
                        }
                        elseif ($NamedAttributeArgumentAst.Argument.VariablePath.UserPath -cne 'true')
                        {
                            $invalidFormat = $true
                        }
                        elseif ($NamedAttributeArgumentAst.ArgumentName -cne 'Mandatory')
                        {
                            $invalidFormat = $true
                        }
                    }
                    catch
                    {
                        $invalidFormat = $true
                    }

                    if ($invalidFormat)
                    {
                        $script:diagnosticRecord['Message'] = $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat

                        $script:diagnosticRecord -as $script:diagnosticRecordType
                    }
                }
            }
        }
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-ParameterBlockMandatoryNamedArgument.ps1' 88
#Region './Public/Measure-ParameterBlockParameterAttribute.ps1' 0
<#
    .SYNOPSIS
        Validates the [Parameter()] attribute for each parameter.

    .DESCRIPTION
        All parameters in a param block must contain a [Parameter()] attribute
        and it must be the first attribute for each parameter and must start with
        a capital letter P.

    .EXAMPLE
        Measure-ParameterBlockParameterAttribute -ParameterAst $parameterAst

    .INPUTS
        [System.Management.Automation.Language.ParameterAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

    .NOTES
        None
#>
function Measure-ParameterBlockParameterAttribute
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ParameterAst]
        $ParameterAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $ParameterAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName
        [System.Boolean] $inAClass = Test-IsInClass -Ast $ParameterAst

        <#
            If we are in a class the parameter attributes are not valid in Classes
            the ParameterValidation attributes are however
        #>
        if (!$inAClass)
        {
            if ($ParameterAst.Attributes.TypeName.FullName -notContains 'parameter')
            {
                $script:diagnosticRecord['Message'] = $localizedData.ParameterBlockParameterAttributeMissing

                $script:diagnosticRecord -as $script:diagnosticRecordType
            }
            elseif ($ParameterAst.Attributes[0].TypeName.FullName -ne 'parameter')
            {
                $script:diagnosticRecord['Message'] = $localizedData.ParameterBlockParameterAttributeWrongPlace

                $script:diagnosticRecord -as $script:diagnosticRecordType
            }
            elseif ($ParameterAst.Attributes[0].TypeName.FullName -cne 'Parameter')
            {
                $script:diagnosticRecord['Message'] = $localizedData.ParameterBlockParameterAttributeLowerCase

                $script:diagnosticRecord -as $script:diagnosticRecordType
            }
        }
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-ParameterBlockParameterAttribute.ps1' 70
#Region './Public/Measure-SwitchStatement.ps1' 0
<#
    .SYNOPSIS
        Validates the switch-statement block braces and new lines around braces.

    .DESCRIPTION
        Each switch-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-SwitchStatement -SwitchStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.SwitchStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-SwitchStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.SwitchStatementAst]
        $SwitchStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $SwitchStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $SwitchStatementAst.Extent
        }

        <#
            Must use an else block here, because otherwise, if there is a
            switch-clause that is formatted wrong it will hit on that
            and return the wrong rule message.
        #>
        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.SwitchStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
        elseif (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.SwitchStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.SwitchStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-SwitchStatement.ps1' 68
#Region './Public/Measure-TryStatement.ps1' 0
<#
    .SYNOPSIS
        Validates the try-statement block braces and new lines around braces.

    .DESCRIPTION
        Each try-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-TryStatement -TryStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.TryStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-TryStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.TryStatementAst]
        $TryStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $TryStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $TryStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.TryStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.TryStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.TryStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-TryStatement.ps1' 64
#Region './Public/Measure-TypeDefinition.ps1' 0
<#
    .SYNOPSIS
        Validates the Class and Enum of PowerShell.

    .DESCRIPTION
        Each Class or Enum must be formatted correctly.

    .EXAMPLE
        Measure-TypeDefinition -TypeDefinitionAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.TypeDefinitionAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-TypeDefinition
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.TypeDefinitionAst]
        $TypeDefinitionAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $TypeDefinitionAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $TypeDefinitionAst.Extent
        }

        if ($TypeDefinitionAst.IsEnum)
        {
            if (Test-StatementOpeningBraceOnSameLine @testParameters)
            {
                $script:diagnosticRecord['Message'] = $localizedData.EnumOpeningBraceNotOnSameLine
                $script:diagnosticRecord -as $diagnosticRecordType
            } # if

            if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
            {
                $script:diagnosticRecord['Message'] = $localizedData.EnumOpeningBraceShouldBeFollowedByNewLine
                $script:diagnosticRecord -as $diagnosticRecordType
            } # if

            if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
            {
                $script:diagnosticRecord['Message'] = $localizedData.EnumOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $script:diagnosticRecord -as $diagnosticRecordType
            } # if
        } # if
        elseif ($TypeDefinitionAst.IsClass)
        {
            if (Test-StatementOpeningBraceOnSameLine @testParameters)
            {
                $script:diagnosticRecord['Message'] = $localizedData.ClassOpeningBraceNotOnSameLine
                $script:diagnosticRecord -as $diagnosticRecordType
            } # if

            if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
            {
                $script:diagnosticRecord['Message'] = $localizedData.ClassOpeningBraceShouldBeFollowedByNewLine
                $script:diagnosticRecord -as $diagnosticRecordType
            } # if

            if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
            {
                $script:diagnosticRecord['Message'] = $localizedData.ClassOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $script:diagnosticRecord -as $diagnosticRecordType
            } # if
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-TypeDefinition.ps1' 86
#Region './Public/Measure-WhileStatement.ps1' 0
<#
    .SYNOPSIS
        Validates the while-statement block braces and new lines around braces.

    .DESCRIPTION
        Each while-statement should have the opening brace on a separate line.
        Also, the opening brace should be followed by a new line.

    .EXAMPLE
        Measure-WhileStatement -WhileStatementAst $ScriptBlockAst

    .INPUTS
        [System.Management.Automation.Language.WhileStatementAst]

    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]

   .NOTES
        None
#>
function Measure-WhileStatement
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.WhileStatementAst]
        $WhileStatementAst
    )

    try
    {
        $script:diagnosticRecord['Extent'] = $WhileStatementAst.Extent
        $script:diagnosticRecord['RuleName'] = $PSCmdlet.MyInvocation.InvocationName

        $testParameters = @{
            StatementBlock = $WhileStatementAst.Extent
        }

        if (Test-StatementOpeningBraceOnSameLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.WhileStatementOpeningBraceNotOnSameLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsNotFollowedByNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.WhileStatementOpeningBraceShouldBeFollowedByNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if

        if (Test-StatementOpeningBraceIsFollowedByMoreThanOneNewLine @testParameters)
        {
            $script:diagnosticRecord['Message'] = $localizedData.WhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
            $script:diagnosticRecord -as $diagnosticRecordType
        } # if
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#EndRegion './Public/Measure-WhileStatement.ps1' 64
#Region './suffix.ps1' 0
# Import Localized Data
Get-LocalizedData -BindingVariable localizedData -DefaultUICulture 'en-US'
#EndRegion './suffix.ps1' 2
