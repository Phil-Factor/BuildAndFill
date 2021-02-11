 /* if your data is in a directory that uses the name of the datasource database,
use the macro '<dbname>' to match the data output routine. 
if you change the name of the database to the source
of the data, remember to specify it without the macro and with the trailing
backslash as normal */

DECLARE @DataFolderLocation sysname = 'C:\BCPData\${datasource}\databaseContents';
DECLARE @CurrentDatabase sysname=db_name();--this database. eg PubsTest
Declare @DataSource sysname='${datasource}'; --'MyProject';
--the project name of the database e.g. Pubs

DECLARE @command NVARCHAR(4000);
DECLARE @CorrectVersion NVARCHAR(40);
DECLARE @DirListingOutput TABLE (Rawinput NVARCHAR(255)); --e.g. 1.1.6
/* read into a table variable the available subdirectories of data via 
a CmdShell command */
--read in a list of all the diirectories 
SELECT @command='dir '+@DataFolderLocation+'\v*  /a:d /b';
INSERT INTO @DirListingOutput(Rawinput) 
  EXECUTE xp_cmdshell @command;
/* extract just the directory names with legal 'semantic Versions'*/
DECLARE @SemanticVersion TABLE
  (
  TheVersion NVARCHAR(30),
  TheType CHAR(12),
  SoFar NVARCHAR(30),
  Major INT,
  Minor INT,
  Patch INT
  );
Print 'getting Data from C:\BCPData\${datasource}\databaseContents'
/* Put into our version table all the available folders with their versions */
INSERT INTO @SemanticVersion (TheVersion, TheType)
  SELECT Substring(Rawinput, PatIndex('%V%.%.%', Rawinput)+1, 30), 'folder'
  FROM @DirListingOutput
  WHERE Rawinput LIKE '%V%.%.%';
IF @@RowCount = 0 
  RAISERROR('Sorry, but %s doesn''nt have any data folders at ${datasource} of the right format (Vd.d.d)',
  16,1,@DataFolderLocation);

/* first we read the flyway schema history to detect what version
the database needs to be at. */
if object_id('dbo.flyway_schema_History') is not null
  INSERT INTO @SemanticVersion (TheVersion, TheType)
    SELECT [version], 'ourVersion' --we need to find the greatest successful version.
      FROM ${flyway:defaultSchema}.flyway_schema_History -- 
      WHERE installed_rank =
         ( --get the PK of the highest successful version recorded
         SELECT Max(Installed_Rank) FROM ${flyway:defaultSchema}.flyway_schema_History WHERE success = 1
         );
else --Uhoh. looks like he's not using Flyway. Is he useing an Extended property?
	begin
	Declare @MaybeWeGotAVersion nvarchar(max)
	SELECT @MaybeWeGotAVersion= convert(nvarchar(max),fn_listextendedproperty.value)
	FROM sys.fn_listextendedproperty(
      N'Database_Info', DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT
      )
	Select  JSON_VALUE ( @MaybeWeGotAVersion , N'lax $[0].Version' ) 
	INSERT INTO @SemanticVersion (TheVersion, TheType)
	Select coalesce(JSON_VALUE ( @MaybeWeGotAVersion , '$[0].Version' ),'1.1.1') as TheVersion,
			'ourVersion' as TheType
	end			

/* now we see what versions of the data are available in the directory 
we parse it into the three integers in three stages. */
--get the major version
UPDATE @SemanticVersion
  SET Major 
    = Substring(TheVersion + '.0.0.0', 1,
                PatIndex('%.%', TheVersion + '.0.0.0') - 1 ),
  SoFar = Stuff(
               TheVersion + '.0.0.0', 1,
               PatIndex('%.%', TheVersion + '.0.0.0'), '' );
--and the minor version
UPDATE @SemanticVersion
  SET Minor = Substring(SoFar, 1, PatIndex('%.%', SoFar) - 1),
  SoFar = Stuff(SoFar, 1, PatIndex('%.%', SoFar), '');
--and the 'patch' version
UPDATE @SemanticVersion SET Patch = 
	Substring(SoFar, 1, PatIndex('%.%', SoFar) - 1 );
DECLARE @VersionOrder TABLE
  (
  TheOrder INT IDENTITY(1, 1),
  TheType CHAR(12) NOT NULL,
  TheVersion NVARCHAR(30) NOT NULL,
  Major INT NOT NULL,
  Minor INT NOT NULL,
  Patch INT NOT NULL
  );
INSERT INTO @VersionOrder (TheVersion, TheType, Major, Minor, Patch)
  SELECT TheVersion, TheType, Major, Minor, Patch
    FROM @SemanticVersion
    ORDER BY Major, Minor, Patch, TheType;
--now we get the version equal or lower than the previous data
SELECT @CorrectVersion=TheVersion
  FROM @VersionOrder
  WHERE TheOrder =
    (
    SELECT Max(TheOrder)
      FROM @VersionOrder
      WHERE TheType = 'folder'
        AND TheOrder < 
		(SELECT TOP 1 TheOrder FROM @VersionOrder 
		 WHERE TheType = 'ourVersion')
    );
 IF @@RowCount = 0 
   RAISERROR('Sorry, but there is no suitable version of the data at %s',
  16,1,@DataFolderLocation);
--SELECT @CorrectVersion;
DISABLE TRIGGER ALL ON DATABASE;
--now disable all constraints
EXEC sp_MSforeachtable 'ALTER TABLE ? NOCHECK CONSTRAINT ALL';
SELECT @command='
Print ''inserting ?''
SET ANSI_NULLS, QUOTED_IDENTIFIER ON;
if ''?''<>''[dbo].[flyway_schema_history]''
BULK INSERT '+@CurrentDatabase+'.?
	FROM '''+@DataFolderLocation+'\V'+@CorrectVersion+'\'+@DataSource+'-?.bcp''
	WITH (
		DATAFILETYPE = ''widenative'',KEEPIDENTITY
		);';
EXEC sp_MSforeachtable @command;
EXEC sp_MSforeachtable 'ALTER TABLE ? with check CHECK CONSTRAINT ALL';
ENABLE TRIGGER ALL ON DATABASE;
