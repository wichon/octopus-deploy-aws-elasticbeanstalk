$SourceDirectoryName = $OctopusParameters["Octopus.Action[$StepName].Output.Package.InstallationDirectoryPath"]
# There could be environments with spaces, we want to avoid problems with file names
$DestinationArchiveFileName = $OctopusParameters['DestinationArchiveFileName'].trim().replace(" ", "_")
$BucketName = $OctopusParameters['BucketName']
$AccessKey = $OctopusParameters['AccessKey'].trim()
$SecretKey = $OctopusParameters['SecretKey'].trim()
$Prefix = $OctopusParameters['Prefix']
$ApplicationName = $OctopusParameters['ApplicationName']
$ApplicationVersion = $OctopusParameters['ApplicationVersion']
$EnvironmentName = $OctopusParameters['EnvironmentName']
$Region = $OctopusParameters['Region']
$Description = $OctopusParameters['Description']

$DestinationFilePath = Join-Path -Path $SourceDirectoryName -ChildPath $DestinationArchiveFileName

if (!$SourceDirectoryName)
{
    Write-Error "No Source Directory name was specified. Please specify the name of the directory to that will be zipped."
    exit -2
}

if (!$DestinationArchiveFileName)
{
    Write-Error "No Destination Archive File name was specified. Please specify the name of the zip file to be created."
    exit -2
}

if (Test-Path $DestinationArchiveFileName)
{
    Write-Host "$DestinationArchiveFileName already exists. Will delete it before we create a new zip file with the same name."
    Remove-Item $DestinationArchiveFileName
}

# Create a new uniquely named temporary file and save its full path, then remove the file created we only need the name
$temporaryFile = [System.IO.Path]::GetTempFileName()
# GetTempFileName creates an empty file
Remove-Item $temporaryFile

# When deploying to a non-windows Elastic Beanstalk environment from a windows enviroment we need to change the 
# zip file paths encoding to match the one used in linux we change '\\' to '/'.
# for this matter we override the default encoder used by the ZipFile package to encode the paths with a custom one.
$source = @"
using System.Text;

namespace Octopus.Devops {
    public class AWSZipEncoder : UTF8Encoding {
        public AWSZipEncoder() {}
        public override byte[] GetBytes(string input) {
            var transform = input.Replace("\\", "/");
            return base.GetBytes(transform);
        }
    }
}
"@

Add-Type -TypeDefinition $source -Language CSharp
$encoder = New-Object -TypeName Octopus.Devops.AWSZipEncoder

[Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem")
$compressionLevel = [System.IO.Compression.CompressionLevel]::Fastest
[System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectoryName, $temporaryFile, $compressionLevel, $false, $encoder);

Write-Host "Creating Zip file $DestinationArchiveFileName with the contents of directory $DestinationArchiveFileName using compression level $CompressionLevel"

Move-Item $temporaryFile $DestinationFilePath

Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"
$key = "$Prefix/$DestinationArchiveFileName"

Set-DefaultAWSRegion -Region $Region
Set-AWSCredentials -AccessKey "$AccessKey" -SecretKey "$SecretKey"
Initialize-AWSDefaults

Write-Host "Uploading application package..."
Write-S3Object -BucketName $BucketName -Key $key -CannedACLName Private -File $DestinationFilePath

Write-Host "Creating application version..."
New-EBApplicationVersion -ApplicationName $ApplicationName -VersionLabel $ApplicationVersion -SourceBundle_S3Bucket $BucketName -SourceBundle_S3Key $key -Description "$Description"

Write-Host "Deploying to ElasticBeanstalk..."
Update-EBEnvironment -EnvironmentName $EnvironmentName -VersionLabel $ApplicationVersion

# Adding a sleep to give time to the deployment process to start
Start-Sleep -Seconds 20

$i=0
$isReady=$FALSE
# wait no more than 10 minutes for the deployment to finish (or 20 sleeps of 30 seconds)
while ((!$isReady) -and ($i -lt 20)) {
    $i++
    $ebHealth = Get-EBEnvironmentHealth -EnvironmentName $EnvironmentName -AttributeName Status
    if ($ebHealth.Status -eq "ready") {
        Write-Host "Deployment was successful :), bye."
        $isReady=$TRUE;        
    } else {
        Write-Host "Deployment is in process ..."
    }
    Start-Sleep -Seconds 30
}

if (!$isReady) {
    Write-Host "Deployment health check failed, check your aws console :'("
}
