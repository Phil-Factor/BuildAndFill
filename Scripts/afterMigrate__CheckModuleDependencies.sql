

/*
** start of the batch that checks the non-schemabound routines **

you use sp_refreshView  for non-schema-bound  views  and spRefreshSQLModule for
non-schema-bound stored procedure, user-defined function, view, DML trigger,
database-level DDL trigger, or server-level DDL trigger.
*/
-- a couple of table variables, one to save the errors ....
DECLARE @Errors TABLE (TheOrder INT IDENTITY, [Description] NVARCHAR(255) NOT NULL);
-- ... and another for the list of non-schemabound routines or modules.
DECLARE @NonSchemaBoundRoutines TABLE
  (
  TheOrder INT IDENTITY PRIMARY KEY,
  TheName sysname NOT NULL,
  TheType sysname NOT NULL
  );
-- we create a table with the name and type of each module
INSERT INTO @NonSchemaBoundRoutines (TheName, TheType)
  SELECT Coalesce(QuoteName(Object_Schema_Name(object_id)) + '.', '')
         + QuoteName(name), Replace(Lower(type_desc), '_', ' ')
    FROM sys.objects
    WHERE type_desc IN
('VIEW', 'SQL_STORED_PROCEDURE', 'SQL_TABLE_VALUED_FUNCTION',
  'SQL_INLINE_TABLE_VALUED_FUNCTION', 'SQL_TRIGGER', 'SQL_SCALAR_FUNCTION'
)
      AND ObjectProperty(object_id, 'IsSchemaBound') = 0;
/* we now brazenly iterate through the table and, for each row, we pass
the name to the system procedure to refresh it  */
DECLARE @ii INT, @iiMax INT; -- iterative variables
--initialise the two variables
SELECT @ii = 1, @iiMax = Max(TheOrder) FROM @NonSchemaBoundRoutines;
--now execute the sys.sp_refreshsqlmodule for each
DECLARE @MyModule sysname, @MyModuleType sysname;
WHILE @ii <= @iiMax
  BEGIN
    SELECT @MyModule = TheName, @MyModuleType = TheType
      FROM @NonSchemaBoundRoutines
      WHERE TheOrder = @ii;
    BEGIN TRY
      EXEC sys.sp_refreshsqlmodule @name = @MyModule;
    END TRY
    BEGIN CATCH
      INSERT INTO @Errors ([Description])
        SELECT 'The ' + @MyModuleType + ' ' + @MyModule
               + ' has a reference to an ' + Error_Message();
    END CATCH;
    SELECT @ii = @ii + 1;
  END;
-- now report all the errors
DECLARE @ErrorMessage NVARCHAR(MAX)
SELECT @ErrorMessage=''
SELECT @ErrorMessage+= '
'+Convert(VARCHAR(5),TheOrder)+' '+[Description] FROM @Errors
IF @@RowCount>0
RAISERROR('SQL Module Dependency errors %s ',16,1,@ErrorMessage)
GO 
