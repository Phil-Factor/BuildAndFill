$ProjectFolder = 'MyPathTo\BuildAndFill'
$Server = 'MyServer'
$Database = 'AdWorks';
$ProjectName='AdventureWorks';
$DataSource='AdventureWorks2016'; #where you got the data from 
$ProjectDescription='A sample project to show how to build a database and fill it with data'
<# you only need this username and password if there is no domain authentication #>
$username = 'Phil Factor'
$port = '1433'
# add a bit of error-checking. Is the project directory there
if (-not (Test-Path "$ProjectFolder"))
   { Write-Error "Sorry, but I couldn't find a project directory at the $ProjectFolder location"}
# ...and is the script directory there?
if (-not (Test-Path "$ProjectFolder\Scripts"))
   { Write-Error "Sorry, but I couldn't find a scripts directory at the $ProjectFolder\Scripts location"}
# now we get the password if necessary
if ($username -ne '') #then it is using SQL Server Credentials
{
	# we see if we've got these stored already
	$SqlEncryptedPasswordFile = "$env:USERPROFILE\$($username)-$SourceServer.xml"
	# test to see if we know about the password in a secure string stored in the user area
	if (Test-Path -path $SqlEncryptedPasswordFile -PathType leaf)
	{
		#has already got this set for this login so fetch it
		$SqlCredentials = Import-CliXml $SqlEncryptedPasswordFile
		
	}
	else #then we have to ask the user for it (once only)
	{
		# hasn't got this set for this login
		$SqlCredentials = get-credential -Credential $UserName
		# Save in the user area 
		$SqlCredentials | Export-CliXml -Path $SqlEncryptedPasswordFile
        <# Export-Clixml only exports encrypted credentials on Windows.
        otherwise it just offers some obfuscation but does not provide encryption. #>
	}
	$Uid = $SqlCredentials.UserName;
	$Pwd = $SqlCredentials.GetNetworkCredential().password

$FlyWayArgs =
    @("-url=jdbc:sqlserver://$($Server):$port;databaseName=$Database", 
	"-locations=filesystem:$ProjectFolder\Scripts", <# the migration folder #>
	"-user=$($SqlCredentials.UserName)", 
	"-password=$($SqlCredentials.GetNetworkCredential().password)")
}
else
{
 $FlyWayArgs=
    @("-url=jdbc:sqlserver://$($Server):$port;databaseName=$Database;integratedSecurity=true".
      "-locations=filesystem:$ProjectFolder\Scripts")<# the migration folder #>
}
$FlyWayArgs+= <# the project variables that we reference with placeholders #>
    @("-placeholders.projectDescription=$ProjectDescription",
      "-placeholders.projectName=$ProjectName",
      "-placeholders.datasource=$DataSource") <# the project variables #>

Flyway migrate @FlyWayArgs -mixed="true"
