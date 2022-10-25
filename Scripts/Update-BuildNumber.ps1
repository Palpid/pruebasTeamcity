<#
.SYNOPSIS

 Script for TeamCity to update assembly-version on each build.

.DESCRIPTION

 PowerShell helper script to be consumed by TeamCity. It is capable of updating AssemblyInfo.cs
 and AssemblyCommonInfo.cs in searching of 'AssemblyVersion' attribute. It can do a full or partial
 replace, later print new version into a specified text file and in way recognized by TeamCity itself
 so it's picked up and displayed there too.

.EXAMPLE
 T:\> Update-BuildNumber -BuildRevision %build.counter%

 Updates program's assembly and assembly-file version's last chunk with current unique build counter
 given by TeamCity on build start.

.EXAMPLE
 T:\> Update-BuildNumber -BuildRevision 11 -SkipAssemblyFileUpdate $True
 
 Update program's assembly version's last chunk with '11' and leaves the assembly-file version as it was before.

.NOTES
 Author:  Paweł Hofman (CodeTitans 2016)

#>
Param(
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName = ('App'),
    [string]$ProjectPath = $null,
    [int32]$BuildMajor = -1,
    [int32]$BuildMinor = -1,
    [int32]$BuildNumber = -1,
    [int32]$BuildRevision = 0,
    [bool]$ForceZeros = $False,
    [bool]$SkipAssemblyVersionUpdate = $False,
    [bool]$SkipAssemblyFileVersionUpdate = $False,
    [bool]$SkipTeamCity = $False,
    [string]$VersionOutputFile=('src\App\undefined.txt')
)

##########################################
# Setup global parameters

# Stop on each error inside the script
$ErrorActionPreference = "Stop"

# Set the path to projects, assumption is this script
# is located inside the 'scripts' folder while application sources
# are under 'src' 
$SolutionDir = $path=$pwd.Path + '\..'
if ($ProjectPath -eq $null)
{
    $ProjectDir = $SolutionDir + '\src\' + $ProjectName
}
else
{
    $ProjectDir = $SolutionDir + '\' + $ProjectPath
}

# Check wether there is expected content
Function Private:Check-AssemblyInfoContent([string]$fileName)
{
    # Assume the file is under 'Properties' subfolder of the project
    $fullFileName = $ProjectDir + '\Properties\' + $fileName;

    #Write-Host "Looking for file: $fullFileName"
    if (![System.IO.File]::Exists($fullFileName))
    {
        $fullFileName = $SolutionDir + '\' + $fileName
        if (![System.IO.File]::Exists($fullFileName))
        {
            return $null
        }
    }

    # Check if expected content is inside
    $content = Get-Content $fullFileName
    $count = ($content | Select-String -pattern "AssemblyVersion").Count

    if ($count -eq 0)
    {
        return $null
    }

    return $fullFileName
}

Function Get-DefaultBuildNumber()
{
    # by default Visual Studio gets the number of days since the beginning of the century:
    return [string][int]((Get-Date -Date (Get-Date -Format d)) - (Get-Date -Date '2000-01-01')).TotalDays
}

#############################################################################################################

$AssemblyInfoFile = Check-AssemblyInfoContent 'GlobalAssemblyInfo.cs'
if ($AssemblyInfoFile -eq $null)
{
    $AssemblyInfoFile = Check-AssemblyInfoContent 'AssemblyInfo.cs'    
}
if ($AssemblyInfoFile -eq $null)
{
    $AssemblyInfoFile = Check-AssemblyInfoContent 'AssemblyCommonInfo.cs'    
}
if ($AssemblyInfoFile -eq $null)
{
    $AssemblyInfoFile = Check-AssemblyInfoContent 'AssemblyInfo.Common.cs'    
}

# Test for input file:
if (![System.IO.File]::Exists($AssemblyInfoFile))
{
    Write-Error "Unable to find assembly version file for project '$ProjectName'!"
    Exit 1
}

# Scan an assembly-info file to look for existing version value:
$content = Get-Content $AssemblyInfoFile
$version = $content | Select-String -pattern "AssemblyVersion" | Out-String
#$version | Foreach-Object { Write-Host $_ }

$version -imatch '\s*\[assembly:\s*AssemblyVersion\s*\(\s*"(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<number>[0-9]+)\.(?<revision>[0-9]+)"\s*\)\s*\]' | Out-Null
if ($matches -eq $null)
{
    $version -imatch '\s*\[assembly:\s*AssemblyVersion\s*\(\s*"(?<major>[0-9]+)\.(?<minor>[0-9]+)\.\*"\s*\)\s*\]' | Out-Null

    if ($matches -eq $null)
    {
        Write-Error 'Unable to find correct assembly version!'
        Exit 2
    }
    else
    {
        $FoundMajor = $matches["major"]
        $FoundMinor = $matches["minor"]
        $FoundNumber = Get-DefaultBuildNumber
        $FoundRevision = 0
    }
}
else
{
    $FoundMajor = $matches["major"]
    $FoundMinor = $matches["minor"]
    $FoundNumber = $matches["number"]
    $FoundRevision = $matches["revision"]
}

#############################################################################################################

# Reuse or replace existing value:
if ($BuildMajor -gt 0)
{
    $FoundMajor = $BuildMajor
}
if ($BuildMinor -gt 0)
{
    $FoundMinor = $BuildMinor
}
if ($BuildNumber -ge 0)
{
    if ($BuildNumber -eq 0)
    {
        $FoundNumber = Get-DefaultBuildNumber
    }
    else
    {
        $FoundNumber = $BuildNumber
    }
}
if ($BuildRevision -le 0)
{
    $BuildRevision = $FoundRevision
}

# Calculate new build number:
if ($ForceZeros)
{
    $VersionText = "{0}.{1}.{2}.{3}" -f "0","0","0",$BuildRevision
}
else
{
    $VersionText = "{0}.{1}.{2}.{3}" -f $FoundMajor,$FoundMinor,$FoundNumber,$BuildRevision
}

#############################################################################################################

# Update the AssemblyInfo.cs file, if required:
if (!$SkipAssemblyVersionUpdate)
{
    $replacementVersion = 'AssemblyVersion("{0}")' -f $VersionText
    $content = $content -Replace 'AssemblyVersion\s*\(\s*"\S+"\s*\)', $replacementVersion
}
if (!$SkipAssemblyFileVersionUpdate)
{
    $replacementFileVersion = 'AssemblyFileVersion("{0}")' -f $VersionText
    $content = $content -Replace 'AssemblyFileVersion\s*\(\s*"\S+"\s*\)', $replacementFileVersion
}

if (!$SkipAssemblyVersionUpdate -Or !$SkipAssemblyFileVersionUpdate)
{
    $content | Out-File $AssemblyInfoFile
}

# Inform TeamCity about new build numer:
if (!$SkipTeamCity)
{
    "##teamcity[buildNumber '{0}']" -f $VersionText
}

#############################################################################################################

# Test for output file:
if (![System.IO.File]::Exists($VersionOutputFile))
{
    $VersionOutputFile = $SolutionDir + '\' + $VersionOutputFile
}

# Save the same version number to specified content-output file (especially useful, when need to check version via HTTP):
if ([System.IO.File]::Exists($VersionOutputFile))
{
    $versionOutputContent = Get-Content $VersionOutputFile
    $replacementVersion = 'version=' + $VersionText
    $versionOutputContent = $versionOutputContent -Replace 'version\s*=\s*\S+\s*', $replacementVersion
    $versionOutputContent | Out-File $VersionOutputFile
    # Write-Host $VersionOutputContent
}
