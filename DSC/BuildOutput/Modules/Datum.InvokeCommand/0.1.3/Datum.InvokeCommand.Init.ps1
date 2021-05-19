$config = Import-PowerShellDataFile -Path $PSScriptRoot\Config\Datum.InvokeCommand.Config.psd1

$regExString = '{0}(?<Content>[\s\S]+?){1}' -f [regex]::Escape($config.Header), [regex]::Escape($config.Footer)

$global:datumInvokeCommandRegEx = New-Object Text.RegularExpressions.Regex($regExString, ('IgnoreCase', 'Compiled'))
