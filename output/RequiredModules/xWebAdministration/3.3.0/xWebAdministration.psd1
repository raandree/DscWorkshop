@{
    # Version number of this module.
    moduleVersion = '3.3.0'

    # ID used to uniquely identify this module
    GUID = 'b3239f27-d7d3-4ae6-a5d2-d9a1c97d6ae4'

    # Author of this module
    Author = 'DSC Community'

    # Company or vendor of this module
    CompanyName = 'DSC Community'

    # Copyright statement for this module
    Copyright = 'Copyright the DSC Community contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Module with DSC Resources for Web Administration'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '4.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion = '4.0'

    # Functions to export from this module
    FunctionsToExport = @()

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    DscResourcesToExport = @('WebApplicationHandler','xIisFeatureDelegation','xIisHandler','xIisLogging','xIisMimeTypeMapping','xIisModule','xSslSettings','xWebApplication','xWebAppPool','xWebAppPoolDefaults','xWebConfigKeyValue','xWebConfigProperty','xWebConfigPropertyCollection','xWebSite','xWebSiteDefaults','xWebVirtualDirectory')

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{

        PSData = @{
            Prerelease = ''

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'DSCResource')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/dsccommunity/xWebAdministration/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/dsccommunity/xWebAdministration'

            # A URL to an icon representing this module.
            IconUri = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [3.3.0] - 2022-06-03

### Deprecated

- **The module _xWebAdministration_ will be renamed to _WebAdministrationDsc_
  ([issue #213](https://github.com/dsccommunity/xWebAdministration/issues/213)).
  The version `v3.3.0` will be the the last release of _xWebAdministration_.
  Version `v4.0.0` will be released as _WebAdministrationDsc_, it will be
  released shortly after the `v3.3.0` release to be able to start transition
  to the new module. The prefix ''x'' will be removed from all resources in
  _WebAdministrationDsc_.**

### Changed

- xWebAdministration
  - Renamed `master` branch to `main` ([issue #591](https://github.com/PowerShell/xWebAdministration/issues/591)).
  - The pipeline will now update the module manifest property `DscResourcesToExport`
    automatically.
  - Only run the CI/CD pipeline on branch _main_ when there are changes to files
    inside the `source` folder.
  - Update the pipeline files to the latest from Sampler.
  - Switched build worker from Windows Server 2016 to Windows Server 2022,
    so that both Windows Server 2019 and Windows Server 2022 is now used.
  - Add resources README.md for wiki documentation.
- CommonTestHelper
  - Removed the helper function `Install-NewSelfSignedCertificateExScript`
    as the script it used is no longer available. Switched to using the
    module _PSPKI_ instead.

### Fixed

- xWebAdministration
  - The component `gitversion` that is used in the pipeline was wrongly configured
    when the repository moved to the new default branch `main`. It no longer throws
    an error when using newer versions of GitVersion.
- xIisLogging
  - Fixed the descriptions for SourceType and SourceName which were incorrectly
    switched around in the `README.md`.

'

        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
