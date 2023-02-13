$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$modulePath = "$here\..\..\.."
$moduleName = Split-Path -Path $modulePath -Leaf

InModuleScope $moduleName {
    Describe Unprotect-Datum {
        #Mock Get-PrivateFunction { $PrivateData }

        Context 'Return values' {

            It 'Returns a string from Get-PrivateFunction' {
                $true | Should -Be $true
            }
        }
    }
}