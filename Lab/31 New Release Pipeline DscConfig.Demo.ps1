﻿param (
    [Parameter()]
    [string]$LabName = 'DscWorkshop'
)

if ((Get-Lab -ErrorAction SilentlyContinue).Name -ne $LabName)
{
    try
    {
        Write-host "Importing lab '$LabName'"
        Import-Lab -Name $LabName -NoValidation -ErrorAction Stop
    }
    catch
    {
        Write-Host "Lab '$LabName' could not be imported. Trying to find a lab with a name starting with 'DscWorkshop*'"
        $possibleLabs = Get-Lab -List | Where-Object { $_ -like 'DscWorkshop*' }
        if ($possibleLabs.Count -gt 1)
        {
            Write-Error "There are multiple 'DscWorkshop' labs ($($possibleLabs -join ', ')). Please remove the ones you don't need."
            exit
        }
        else
        {
            Write-Host "Importing lab '$possibleLabs'"
            Import-Lab -Name $possibleLabs -NoValidation -ErrorAction Stop
        }
    }
}

$here = $PSScriptRoot
$projectGitUrl = 'https://github.com/raandree/DscConfig.Demo'
$projectName = $projectGitUrl.Substring($projectGitUrl.LastIndexOf('/') + 1)
$collectionName = 'AutomatedLab'
$gitVersion = @{
    Publisher = 'GitTools'
    Extension = 'GitVersion'
    Version   = '5.0.1.3'
    VsixPath  = 'C:\gittools.gitversion-5.0.1.3.vsix'
}
$lab = Get-Lab
$devOpsServer = Get-LabVM -Role AzDevOps
$devOpsWorker = Get-LabVM -Role HyperV
$devOpsHostName = $devOpsServer.FQDN
$nugetServer = Get-LabVM -Role AzDevOps
$nugetFeed = Get-LabTfsFeed -ComputerName $nugetServer -FeedName PowerShell

$devOpsRole = $devOpsServer.Roles | Where-Object Name -EQ AzDevOps
$devOpsCred = $devOpsServer.GetCredential($lab)
$devOpsPort = 8080

# Which will make use of Azure DevOps, clone the stuff, add the necessary build step, publish the test results and so on
# You will see two remotes, Origin (Our code on GitHub) and Azure DevOps (Our code pushed to your lab)
Write-ScreenInfo 'Creating Azure DevOps project and cloning from GitHub...' -NoNewLine

Copy-LabFileItem -Path $here\LabData\gittools.gitversion-5.0.1.3.vsix -ComputerName $devOpsServer
Invoke-LabCommand -ActivityName "Uploading 'GitVersion' extension" -ComputerName $devOpsServer -ScriptBlock {

    $param = @{
        Uri         = "https://$($devOpsHostName):$devOpsPort/_apis/gallery/extensions?api-version=3.0-preview.1"
        Credential  = $devOpsCred
        Body        = '{{"extensionManifest": "{0}"}}' -f ([Convert]::ToBase64String([IO.File]::ReadAllBytes($gitVersion.VsixPath)))
        Method      = 'POST'
        ContentType = 'application/json'
    }
    if ($PSVersionTable.PSEdition -eq 'Core')
    {
        $param.Add('SkipCertificateCheck', $true)
    }

    $null = (Invoke-RestMethod @param)

} -Variable (Get-Variable -Name devOpsCred, devOpsHostName, devOpsPort, collectionName, gitVersion)

New-LabReleasePipeline -ProjectName $projectName -SourceRepository $projectGitUrl -CodeUploadMethod FileCopy

Invoke-LabCommand -ActivityName 'Bootstrap NuGet.exe' -ComputerName $devOpsServer, $devOpsWorker -ScriptBlock {
    $nugetPath = 'C:\NuGet'
    $nugetPathAllUsers = "$([System.Environment]::GetFolderPath('CommonApplicationData'))\Microsoft\Windows\PowerShell\PowerShellGet\NuGet.exe"
    $nugetPathCurrentUser = "$([System.Environment]::GetFolderPath('LocalApplicationData'))\Microsoft\Windows\PowerShell\PowerShellGet\NuGet.exe"

    if (-not (Test-Path -Path $nugetPath))
    {
        mkdir -Path $nugetPath
    }

    $hasNuget = if (Test-Path -Path $nugetPathAllUsers)
    {
        $nugetExe = Get-Item -Path $nugetPathAllUsers
        Write-Host "'nuget.exe' exist in '$nugetPathAllUsers' with version '$($nugetExe.VersionInfo.FileVersionRaw)'"

        if ($nugetExe.VersionInfo.FileVersionRaw -gt '5.11')
        {
            $true
        }
    }

    if (-not $hasNuget)
    {
        if (Test-Path -Path $nugetPathCurrentUser)
        {
            $nugetExe = Get-Item -Path $nugetPathCurrentUser
            Write-Host "'nuget.exe' exist in '$nugetPathCurrentUser' with version '$($nugetExe.VersionInfo.FileVersionRaw)'"

            if ($nugetExe.VersionInfo.FileVersionRaw -gt '5.11')
            {
                $hasNuget = $true
            }
        }
    }

    if (-not $hasNuget)
    {
        Write-Host "'Nuget.exe' does not exist in ProgramData nor the local users profile, downloading into the users profile..."

        Invoke-WebRequest -Uri 'https://aka.ms/psget-nugetexe' -OutFile $nugetPathCurrentUser -ErrorAction Stop

        if (Test-Path -Path $nugetPathCurrentUser)
        {
            $nugetExe = Get-Item -Path $nugetPathCurrentUser -ErrorAction SilentlyContinue
            Write-Host "'nuget.exe' exist in '$nugetPathCurrentUser' with version '$($nugetExe.VersionInfo.FileVersionRaw)'"

            if ($nugetExe.VersionInfo.FileVersionRaw -lt '5.11')
            {
                Write-Host "'nuget.exe' has the version '$($nugetExe.VersionInfo.FileVersionRaw)' and needs to be updated."
                Invoke-WebRequest -Uri 'https://aka.ms/psget-nugetexe' -OutFile $nugetPathCurrentUser -ErrorAction Stop
            }
        }
        else
        {
            Write-Host "'nuget.exe' does not exist in the local profile and will be downloaded."
            Invoke-WebRequest -Uri 'https://aka.ms/psget-nugetexe' -OutFile $nugetPathCurrentUser -ErrorAction Stop
        }
    }
    else
    {
        Write-Host "OK: NuGet version $($nugetExe.VersionInfo.FileVersionRaw) in directory '$($nugetExe.Directory)' works"
    }

    Copy-Item -Path $nugetExe -Destination $nugetPath

    [System.Environment]::SetEnvironmentVariable('Path', $env:Path + ';C:\NuGet', 'Machine')
}

Invoke-LabCommand -ActivityName "Installing 'GitVersion' extension" -ComputerName $devOpsServer -ScriptBlock {

    Start-Sleep -Seconds 10

    $param = @{
        Uri         = "https://$($devOpsHostName):$devOpsPort/$collectionName/_apis/extensionmanagement/installedextensionsbyname/$($gitVersion.Publisher)/$($gitVersion.Extension)/$($gitVersion.Version)?api-version=5.0-preview.1"
        Credential  = $devOpsCred
        Method      = 'POST'
        ContentType = 'application/json'
    }
    if ($PSVersionTable.PSEdition -eq 'Core')
    {
        $param.Add('SkipCertificateCheck', $true)
    }

    $null = (Invoke-RestMethod @param)

} -Variable (Get-Variable -Name devOpsCred, devOpsHostName, devOpsPort, collectionName, gitVersion)

Invoke-LabCommand -ActivityName 'Set Repository and create Build Pipeline' -ScriptBlock {

    Set-Location -Path C:\Git\DscConfig.Demo
    git checkout main *>$null
    Remove-Item -Path '.\azure-pipelines.yml'
    (Get-Content -Path '.\azure-pipelines On-Prem.yml' -Raw) -replace 'RepositoryUri_WillBeChanged', $nugetFeed.NugetV2Url | Set-Content -Path .\azure-pipelines.yml
    (Get-Content -Path .\Resolve-Dependency.psd1 -Raw) -replace 'PSGallery', 'PowerShell' | Set-Content -Path .\Resolve-Dependency.psd1

    $content = [System.Collections.ArrayList](Get-Content -Path .\Resolve-Dependency.psd1)
    $content.Insert(3, '    AllowOldPowerShellGetModule = $true # this is still required because of dependencies not following semantic versioning')
    $content | Set-Content -Path .\Resolve-Dependency.psd1

    (Get-Content -Path .\RequiredModules.psd1 -Raw) -replace 'PSGallery', 'PowerShell' | Set-Content -Path .\RequiredModules.psd1
    git add .
    git commit -m 'Set RepositoryUri and create Build Pipeline'
    git push 2>$null

} -ComputerName $devOpsServer -Variable (Get-Variable -Name nugetFeed)

Write-Host 'Restarting Azure DevOps Server and worker machine...' -NoNewline
Restart-LabVM -ComputerName (Get-LabVM -Role AzDevOps, HyperV) -Wait -NoDisplay
Write-Host 'done'

Write-ScreenInfo done
