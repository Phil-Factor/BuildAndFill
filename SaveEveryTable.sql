
/* It is important to declare your destination for the data. This is slightly
complicated by the fact that you may want to take data from slightly differently
named databases from the 'project' name for the database. Like 'Adventureworks' might
be your 'datasource' name and you might take data from 'currentDatabase' 
Adventureworks2016.
If you want to add a directory with the name of the datasource database
(the data donor) then add the macro <dbname>. The application will swap that
out for the Data source name. The system obligingly tries to create the directory
if it doesn't exist so with great power comes a certain level of responsibility:
Well, it should do. */

--this first line must be changed to suit your setup 
DECLARE @DataFolderLocation sysname = 'C:\BCPData\<dbname>databaseContents';
DECLARE @CurrentDatabase sysname=Db_Name();--this database. eg PubsTest
--this name must be the name of the project database. 
Declare @DataSource sysname=Db_Name();--the project name of the database e.g. Pubs
--automatically substitute the current database name
Select @DataFolderLocation  = replace(@DataFolderLocation,'<dbname>',@DataSource+'\')
-- you may occasionally have a database of a different name with the data.
-- To allow advanced options to be changed.
EXEC sp_configure 'show advanced options', 1;
-- To update the currently configured value for advanced options.
RECONFIGURE WITH OVERRIDE;
-- To enable the feature.
EXEC sp_configure 'xp_cmdshell', 1;
-- To update the currently configured value for this feature.
RECONFIGURE WITH OVERRIDE;
Declare @Version Nvarchar(40)
/* first we read the flyway schema history to detect what version
the database needs to be at. */
if object_id('dbo.flyway_schema_History') is not null --is it a flyway database
	Begin
	SELECT @Version=[version] --we need to find the greatest successful version.
	  FROM dbo.flyway_schema_History -- 
	  WHERE installed_rank = 
		(--get the PK of the highest successful version recorded
		SELECT Max(Installed_Rank) 
		FROM dbo.flyway_schema_History 
		WHERE success = 1);
	end
else --Ah. This isn't a flyway-versioned database
	begin --let's hope it has an extended property with it.
	Declare @MaybeWeGotAVersion nvarchar(max)
	SELECT @MaybeWeGotAVersion= convert(nvarchar(max),fn_listextendedproperty.value)
	FROM sys.fn_listextendedproperty(
      N'Database_Info', DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT
      )
	Select @Version=coalesce(JSON_VALUE ( @MaybeWeGotAVersion , N'lax $[0].Version' ),'1.1.3You add any prior migration files (previous versions), renamed to the flyway convention, ')
	end	--we default to		

/* We now check to see if the path exists. If it doesn't, then we create it.  */
DECLARE @command NVARCHAR(4000);
Select @command= 'if not exist "'+@DataFolderLocation+'\" mkdir "'+@DataFolderLocation+'"'
--Select @command
execute xp_cmdshell @command
Select @command= 'if not exist "'+@DataFolderLocation+'\V'+@version+'\" mkdir "'+@DataFolderLocation+'\V'+@version+'"'
--Select @command
execute xp_cmdshell @command
/* Dont write out the flyway_schema_history table. It is just too risky */
Select @command='
if ''?''<>''[dbo].[flyway_schema_history]''
	begin
	Print ''writing out '+@CurrentDatabase+'.?''
execute xp_cmdshell ''bcp '+@CurrentDatabase+'.? OUT '+@DataFolderLocation+'\V'+@version+'\'+@DataSource+'-?.bcp -T -N''
	end'
--Select @command
EXEC sp_MSforeachtable @command;
-- we now prevent lesser mortals from using this feature now that we're finished.
EXEC sp_configure 'xp_cmdshell',0;
GO

-- EXEC sp_MSforeachtable 'SELECT OBJECTPROPERTY(OBJECT_ID(N''?''), ''IsUserTable'')'













