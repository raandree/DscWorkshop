@{

    RootModule        = 'Datum.InvokeCommand.psm1'

    ModuleVersion     = '0.1.3'

    GUID              = '31b6472c-069c-40c2-aaa9-ac8c2de55081'

    Author            = 'Raimund Andree'

    CompanyName       = 'NA'

    Copyright         = '(c) 2019 Raimund Andree. All rights reserved.'

    Description       = 'Datum Handler module to run PowerShell commands within a Datum'

    FunctionsToExport = @('Invoke-InvokeCommandAction','Test-InvokeCommandFilter')

    ScriptsToProcess  = 'Datum.InvokeCommand.Init.ps1'

    PowerShellVersion = '4.0'

    PrivateData       = @{

        PSData = @{

            Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResource', 'Datum')

            LicenseUri   = 'https://github.com/raandree/Datum.InvokeCommand/blob/master/LICENSE'

            ProjectUri   = 'https://github.com/raandree/Datum.InvokeCommand'

            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            Prerelease   = ''

            ReleaseNotes = '## [0.0.1] - 2021-03-09

### Added

- Support for expandable strings
- Configurable Header and Footer
- Content is now evaluated with RegEx + PowerShell Parser
- Gives access to Node and Datum variable
- Added function ''Get-RelativeFileName''
- Resolves nested references

'

        }

    }

}




