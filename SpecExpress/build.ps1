properties { 
  
	#Paths
	$base_directory		=	resolve-path .
	$src_directory 		=   "$base_directory\src"	
	$build_directory 	=	"$base_directory\build"
	$release_directory 	=	"$base_directory\deploy"
	$tools_directory 	=	"$base_directory\tools"
	$archive_directory 	=	"$base_directory\archive"
	$NuGetPackDir		=   "$base_directory\nuget"

  # ****************  CONFIGURE ****************     	
    #Version
	$revision = Get-RevisionFromGit $src_directory	
	$version = "1.6.1.$revision"
}

$framework = '4.0'
task default -depends Build, Test, Deploy

task Clean { 
	if (test-path $build_directory) {  
		remove-item -force -recurse $build_directory -ErrorAction SilentlyContinue | Out-Null
	}		
} 
 
task Init -depends Clean { 	
	new-item $build_directory -itemType directory | Out-Null	
} 

task Build -depends Init {
	Create-AssemblyInfo 

    write-host "building $solution_file"
	Exec { msbuild  /verbosity:m /p:Configuration="Release" /p:keyfile="$tools_directory\key\specexpress.key" /p:Platform="Any CPU" /p:OutDir="$build_directory"\\ "$src_directory\SpecExpress.sln" /t:Clean /t:Build }
}

task Test  -depends Build {	
	#NUnit	
	$test_runner 		=	"$tools_directory\nunit\nunit-console.exe"
	exec {&$test_runner "$build_directory\SpecExpress.Test.dll" } 	
}

task Deploy  -depends Build,Test{
	#clean release dir
	remove-item -force -recurse -exclude License.txt, *.svn $release_directory\* | Out-Null

	#copy from build to release
	copy-item $build_directory\SpecExpress*.* $release_directory -exclude *test*, *.xml	
	
	#zips and copies to Archive
	write-host "Zipping files"
	Zip -source "$release_directory\" -dest "$archive_directory\SpecExpress-$version.zip"
}

function Create-AssemblyInfo {
	write-host "Creating Project AssemblyInfo"
	#generate assemblies
	get-childitem $src_directory -recurse -include "Properties"  |
        foreach {		
			$projectPath = $_.Parent.FullName			
			Add-Assembly-Info -file "$projectPath\Properties\AssemblyInfo.cs" -title $_.Parent.Name -version "$version" -copyright "Copyright, Alan Baker and Randy Bell 2011" -snkeyfile "..\\..\\tools\\keys\\SpecExpress.key"
        }
}
#Custom Functions
function Get-RevisionFromSVN([string]$path) {
	Write-Host "Fetching revision from subversion"
	#need cmd to use pipe output to file
	exec{cmd /c ".\tools\svn\svn.exe log $path --xml --limit 1 > revision.xml"}
	$xml = [xml] (get-content "revision.xml")
	$revision = $xml.SelectSingleNode("/log/logentry").revision
	remove-item -force revision.xml	
	Write-Host "Subversion Repository Version: $revision"	
	return $revision
}

function Get-RevisionFromGit([string]$path) {
	Write-Host "Fetchin revision from Git"
	# git describe will return a string in the format of <last tag>-<number of commits since tag>-<short guid>
	$ver = Invoke-Expression 'git describe'
	# Get revision by matching the <number of cimmits since last tag> portion of the description.
	$isMatch = $ver -match "(?<=-)\d*"
	if ($isMatch )
	{
		return $matches[0]
	}
	else
	{
		return ""
	}
}

function Add-Assembly-Info
{
param(
	[string]$clsCompliant = "true",
	[string]$title, 
	[string]$description, 
	[string]$company, 
	[string]$product, 
	[string]$copyright, 
	[string]$version,
	[string]$snkeyfile = "",
	[string]$file = $(throw "file is a required parameter.",
	[object[]]$WebResources)
)
  $asmInfo = "using System;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

[assembly: ComVisibleAttribute(false)]
[assembly: AssemblyTitleAttribute(""$title"")]
[assembly: AssemblyDescriptionAttribute(""$description"")]
[assembly: AssemblyCompanyAttribute(""$company"")]
[assembly: AssemblyProductAttribute(""$product"")]
[assembly: AssemblyCopyrightAttribute(""$copyright"")]
[assembly: AssemblyVersionAttribute(""$version"")]
[assembly: AssemblyInformationalVersionAttribute(""$version"")]
[assembly: AssemblyFileVersionAttribute(""$version"")]
[assembly: AssemblyDelaySignAttribute(false)]
"

	if ($WebResources)
	{	
		$asmInfo = "using System.Web.UI;`n" + $asmInfo
		foreach($resource in $WebResources)
		{
			$asmInfo = $asmInfo + "[assembly: WebResource(""" +  $resource.WebResource + """ , """ + $resource.ContentType + """)]`n"
		}
	}

	$dir = [System.IO.Path]::GetDirectoryName($file)
	if ([System.IO.Directory]::Exists($dir) -eq $false)
	{
		Write-Host "Creating directory $dir"
		[System.IO.Directory]::CreateDirectory($dir)
	}
	Write-Host "Generating assembly info file: $file"
	Write-Output $asmInfo > $file
}

function Zip([string]$source, [string]$dest) {
	[void] [System.Reflection.Assembly]::LoadFrom("$tools_directory\psake\ICSharpCode.SharpZipLib.dll")
	$zip = new-object ICSharpCode.SharpZipLib.Zip.FastZip
	write-host "Zipping $source to $dest"  
	$zip.CreateZip("$dest", "$source", $true, "^((?!.svn).)*$")
}
	