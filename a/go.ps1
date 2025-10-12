Import-Module ..\output\RequiredModules\ComputerManagementDsc\9.2.0\Modules\DscResource.Common\0.18.0\DscResource.Common.psd1

$1 = Get-Content -Path $PSScriptRoot\1\DSCFile01.yml -Raw | ConvertFrom-Yaml
$2 = Get-Content -Path $PSScriptRoot\1\DSCFile01.yml -Raw | ConvertFrom-Yaml

Compare-DscParameterState -CurrentValues $1 -DesiredValues $2 -SortArrayValues -Verbose
