@{

    RootModule        = 'datum.psm1'

    ModuleVersion     = '0.41.0'

    GUID              = 'e176662d-46b8-4900-8de5-e84f9b4366ee'

    Author            = 'Gael Colas'

    CompanyName       = 'SynEdgy Limited'

    Copyright         = '(c) 2020 Gael Colas. All rights reserved.'

    Description       = 'Module to manage Hierarchical Configuration Data.'

    PowerShellVersion = '5.1'

    RequiredModules   = @(
        'powershell-yaml'
    )

    ScriptsToProcess  = @(
        './ScriptsToProcess/Resolve-NodeProperty.ps1'
    )

    FunctionsToExport = @('Clear-DatumRsopCache','ConvertTo-Datum','Get-DatumRsop','Get-DatumRsopCache','Get-DatumSourceFile','Get-FileProviderData','Get-MergeStrategyFromPath','Invoke-TestHandlerAction','Merge-Datum','New-DatumFileProvider','New-DatumStructure','Resolve-Datum','Resolve-DatumPath','Test-TestHandlerFilter')

    AliasesToExport   = ''

    PrivateData       = @{

        PSData = @{

            Tags         = @('Datum', 'Hiera', 'DSC', 'DesiredStateConfiguration', 'hierarchical', 'ConfigurationData', 'ConfigData')

            LicenseUri   = 'https://github.com/gaelcolas/Datum/blob/master/LICENSE'

            ProjectUri   = 'https://github.com/gaelcolas/Datum/'

            ReleaseNotes = '## [0.41.0-preview0002] - 2025-03-25

### Added

- Added Pester tests for credential handling.
- Added knockout support for basetype arrays.
- Added cleanup of knockout items.

### Changed

- Adjusted integration tests for knockout of basetype array items and hashtables keys.
- Updated build scripts to current version of Sampler (0.118.3-preview0001).
- Fixed `ConvertTo-Datum` always returns `$null` when DatumHandler returns `$false` (#139)
- Fixed PowerShell 7 compatibility of Copy-Object integration test.

### Changed

- Adjusted integration tests for knockout of basetype array items and hashtables keys

### Fixed

- Fixed `ConvertTo-Datum` always returns `$null` when DatumHandler returns `$false` (#139).
- Fixed `Merge-DatumArray` does not return an array when merged array contains a single hashtable.
- Fixed and extended tests for `Copy-Object`.
- Fixed PowerShell 7 compatibility of Copy-Object integration test.

'

            Prerelease   = 'preview0002'

        }
    }
}
