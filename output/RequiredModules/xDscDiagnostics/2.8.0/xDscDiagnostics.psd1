@{
    RootModule        = 'xDscDiagnostics.psm1'

    ModuleVersion     = '2.8.0'

    GUID              = 'ef098cb4-f7e9-4763-b636-0cd9799e1c9a'

    Author            = 'DSC Community'
    CompanyName       = 'DSC Community'
    Copyright         = 'Copyright the DSC Community contributors. All rights reserved.'

    Description       = 'Module to help in reading details from DSC events.'

    PowerShellVersion = '4.0'

    CLRVersion        = '4.0'

    # Functions to export from this module
    FunctionsToExport = @('Get-xDscConfigurationDetail','Get-xDscDiagnosticsZipDataPoint','Get-xDscOperation','New-xDscDiagnosticsZip','Trace-xDscOperation','Unprotect-xDscConfiguration','Update-xDscEventLogStatus')

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = 'Get-xDscDiagnosticsZip'

    DscResourcesToExport = @()

    NestedModules     = @()

    PrivateData       = @{
        PSData = @{
            # Set to a prerelease string value if the release should be a prerelease.
            Prerelease = ''

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'Diagnostics')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/xDscDiagnostics/blob/master/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/xDscDiagnostics'

            # A URL to an icon representing this module.
            IconUri = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [2.8.0] - 2020-05-01

### Added

- Added automatic release with a new CI pipeline.

### Fixed

- Fixes #52: Error ''Index operation failed; the array index evaluated to null.''

'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}









