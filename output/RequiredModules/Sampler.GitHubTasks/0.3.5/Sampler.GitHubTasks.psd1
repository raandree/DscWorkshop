@{

    # Script module or binary module file associated with this manifest.
    RootModule = 'Sampler.GitHubTasks.psm1'

    # Version number of this module.
    ModuleVersion     = '0.3.5'

    # Supported PSEditions
    # CompatiblePSEditions = @()

    # ID used to uniquely identify this module
    GUID              = 'eee2dde6-0767-4c17-a4b0-ea303310124b'

    # Author of this module
    Author            = 'Gael Colas'

    # Company or vendor of this module
    CompanyName       = 'SynEdgy Limited'

    # Copyright statement for this module
    Copyright         = '(c) Gael Colas. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Sampler tasks for GitHub integrations'

    # Minimum version of the PowerShell engine required by this module
    # PowerShellVersion = ''

    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @('PowerShellForGitHub')

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = 'Get-GHOwnerRepoFromRemoteUrl'

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport   = ''

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport   = '*'

    # DSC resources to export from this module
    DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData       = @{

        PSData = @{

            Prerelease   = 'preview0002'
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Sampler', 'build', 'tasks', 'InvokeBuild')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/gaelcolas/Sampler.GitHubTasks/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/gaelcolas/Sampler.GitHubTasks'

            # A URL to an icon representing this module.
            IconUri = 'https://raw.githubusercontent.com/gaelcolas/Sampler.GitHubTasks/main/source/assets/sampler_GitHubTasks.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [0.3.5-preview0002] - 2022-06-08

### Added

- Created module with GitHub tasks from Sampler.
- Support to add assets to GitHub released by defining the `ReleaseAssets` key in `build.yml` GitHubConfig.
- Added logo.
- Added Get-GHOwnerRepoFromRemoteUrl function.

### Removed

- Removed GitHub Access Token from variable being displayed during build. Fixes Issue #17.

### Changed

- Fixed Erroring when "$ProjectName.$ModuleVersion.nupkg" is not available (i.e. when using asset list in `Build.yaml`).
- Fixed tasks to use the new Sampler version and its public functions.
- Fixed RootModule not loaded because of Module Manifest.
- Making this project use the prerelease version of Sampler for testing.
- Display GitHub Release info if already exists.
- GitHub New PR to use Owner/Repo name.
- Updated publish workflow in build.yml to Create GH PR upon release.
- Updated the Readme with the icon.
- Adding delay after creating release to make sure the tag is available at next git pull.
- Updating when to skip the Create Changelog PR task (adding -ListAvailable).
- Task `Publish_release_to_GitHub`
  - Removed unnecessary code line ([issue #22](https://github.com/gaelcolas/Sampler.GitHubTasks/issues/22)).
  - Now the command `New-GitHubRelease` only outputs verbose information
    if `$VerbosePreference` says so.

### Fixed

- Fixed task error when the PackageToRelease does not exist (i.e. it''s not a module being built creating the .nupkg).
- Fixed typo when adding debug output for GH task.
- Fixed using the `Set-SamplerTaskVariable` in GH tasks.
- Fixed the Azure DevOps pipeline to build on Ubunt latest.
'

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''

}
