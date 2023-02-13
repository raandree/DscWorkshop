$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$modulePath = "$here\..\..\.."
$moduleName = Split-Path -Path $modulePath -Leaf

InModuleScope $moduleName {
    Describe Invoke-ProtectedDatumAction {
       Mock UnProtect-Datum { $true }

        Context 'Basic test' {

            It 'The command should return true' {
                Invoke-ProtectedDatumAction -InputObject "string" -PlainTextPassword 'P@ssw0rd' | Should -be $true
            }
        }
    }
}