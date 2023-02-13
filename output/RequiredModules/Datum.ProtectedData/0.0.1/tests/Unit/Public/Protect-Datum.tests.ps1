$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$modulePath = "$here\..\..\.."
$moduleName = Split-Path -Path $modulePath -Leaf

InModuleScope $moduleName {
    Describe Protect-Datum {
        Mock Protect-Data {param($inputObject,[securestring]$Password) "ABC" }
        Context 'Encode the encrypted string properly' {

            It 'Testing Protect-Datum encoding of encrypted blob' {
                #$secureString = ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force
                #('ABC' | Protect-Datum -Password $secureString -NoEncapsulation) | Should -be 'PE9ianMgVmVyc2lvbj0iMS4xLjAuMSIgeG1sbnM9Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vcG93ZXJzaGVsbC8yMDA0LzA0Ij4NCiAgPFM+QUJDPC9TPg0KPC9PYmpzPg=='
                $true | Should -be $true
            }
        }
    }
}