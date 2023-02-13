$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$modulePath = "$here\..\..\.."
$moduleName = Split-Path -Path $modulePath -Leaf

InModuleScope $moduleName {
    Describe Test-ProtectedDatumFilter {
        #Mock Get-PrivateFunction { $PrivateData }

        Context 'Return true when format matches' {
            It 'Basic test of encapsulated string' {
                Test-ProtectedDatumFilter -InputObject '[ENC=ABC]' | Should -be $true
            }
        }
    }
}