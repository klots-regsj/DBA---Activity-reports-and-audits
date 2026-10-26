
USE [master];
GO

/*
===============================================================================
DBA DATABASE - CREATE
===============================================================================
Name          : DBA
Purpose       : Create DBA database using SQL Server instance default paths
Compatibility : SQL Server 2012+
Data          : Instance default data directory (UserDB)
Log           : Instance default log directory (TLOG)
===============================================================================
*/

DECLARE @DataPath NVARCHAR(4000);
DECLARE @LogPath  NVARCHAR(4000);
DECLARE @SQL      NVARCHAR(MAX);

IF DB_ID(N'DBA') IS NOT NULL
BEGIN
    PRINT 'Database DBA already exists.';
END
ELSE
BEGIN
    -- Read instance default paths
    SELECT
        @DataPath = CONVERT(NVARCHAR(4000),
            SERVERPROPERTY('InstanceDefaultDataPath')),
        @LogPath = CONVERT(NVARCHAR(4000),
            SERVERPROPERTY('InstanceDefaultLogPath'));

    -- SQL Server 2012 fallback
    IF @DataPath IS NULL OR @LogPath IS NULL
    BEGIN
        RAISERROR(
            'Unable to determine instance default data/log paths.',
            16, 1
        );
    END
    ELSE
    BEGIN
        -- Ensure trailing backslash
        IF RIGHT(@DataPath, 1) <> N'\'
            SET @DataPath += N'\';

        IF RIGHT(@LogPath, 1) <> N'\'
            SET @LogPath += N'\';

        SET @SQL = N'
CREATE DATABASE [DBA]
ON PRIMARY
(
    NAME = N''DBA'',
    FILENAME = N''' + REPLACE(@DataPath, '''', '''''') + N'DBA.mdf'',
    SIZE = 524288KB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 1048576KB
)
LOG ON
(
    NAME = N''DBA_log'',
    FILENAME = N''' + REPLACE(@LogPath, '''', '''''') + N'DBA_log.ldf'',
    SIZE = 262144KB,
    MAXSIZE = 2048GB,
    FILEGROWTH = 1048576KB
);';

        PRINT 'Data path: ' + @DataPath;
        PRINT 'Log path : ' + @LogPath;

        EXEC sys.sp_executesql @SQL;
    END
END;
GO
