$SourceDirectoryName = $OctopusParameters["Octopus.Action[$StepName].Output.Package.InstallationDirectoryPath"]
# There could be environments with spaces, we want to avoid problems with file names
$DestinationArchiveFileName = $OctopusParameters['DestinationArchiveFileName'].trim().replace(" ", "_")
$BucketName = $OctopusParameters['BucketName']
$AccessKey = $OctopusParameters['AccessKey'].trim()
$SecretKey = $OctopusParameters['SecretKey'].trim()
$ApplicationName = $OctopusParameters['ApplicationName']
$ApplicationVersion = $OctopusParameters['ApplicationVersion']
$EnvironmentName = $OctopusParameters['EnvironmentName']
$Region = $OctopusParameters['Region']
$Description = $OctopusParameters['Description']
$parametersFile = Join-Path $SourceDirectoryName $OctopusParameters['MSDeployParametersFilePath']
$ebConfigFile = Join-Path $SourceDirectoryName $OctopusParameters['EBConfigFilePath']

$DestinationFilePath = Join-Path -Path $SourceDirectoryName -ChildPath $DestinationArchiveFileName

$env:Path += ";C:\Program Files (x86)\AWS Tools\Deployment Tool\;C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\"

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

Write-Host "Creating WebDeploy package file $DestinationArchiveFileName with the contents of directory $SourceDirectoryName"

msdeploy.exe -verb:sync -source:iisApp="$SourceDirectoryName" -dest:package="$DestinationArchiveFileName" -declareParamFile="$parametersFile"

Write-Host "Applying transformations in place to AwsDeploy configuration file $ebConfigFile"

$ebConfigContent = (Get-Content $ebConfigFile)
foreach ($key in $OctopusParameters.keys) {
	$ebConfigContent = $ebConfigContent -replace "#{$key}",$OctopusParameters[$key].trim()
}
Set-Content $ebConfigFile $ebConfigContent

Write-Host "Deploying to ElasticBeanstalk ..."

awsdeploy.exe /r $ebConfigFile 

# sleep to give time to the deployment process to start
Start-Sleep -Seconds 20

$i=0
$isReady=$FALSE
# wait no more than 10 minutes for the deployment to finish (or 20 sleeps of 30 seconds)
while ((!$isReady) -and ($i -lt 20)) {
    $i++
    $ebHealth = Get-EBEnvironment -EnvironmentName $EnvironmentName
    if ($ebHealth.Status -eq "Ready") {
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
