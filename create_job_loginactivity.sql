
/*
===============================================================================
DBA - LOGIN ACTIVITY COLLECTION JOB - VERSION 1.0
===============================================================================
Name          : create_job_loginactivity.sql
Purpose       : Create a SQL Server Agent job that collects active user
                sessions and maintains historical login activity records.

Database      : DBA
Schema        : dbo
Table         : dbo.LoginActivity
Job Name      : DBA - Loginactivity
Job Step      : Get logins
Schedule      : Every 1 minute
Job Owner     : sa

Compatibility : SQL Server 2012+
AG Handling   : Supports standalone SQL Server instances and Always On
                Availability Groups.

                DatabaseName identifies the database associated with
                the observed session.

                AGName identifies the Availability Group, if applicable.

                ReplicaRole identifies the local replica role:
                    PRIMARY
                    SECONDARY
                    STANDALONE
                    UNKNOWN

Collection    :
    - Collects active user sessions from SQL Server DMVs.
    - Excludes system sessions and the collection session itself.
    - Records original login, database, application, hostname and IP.
    - Identifies AG membership and local replica role.
    - Uses DISTINCT to avoid duplicate session signatures.

Session Key   :
    A session signature consists of:
        ServerName
        LoginName
        DatabaseName
        AGName
        ReplicaRole
        Application
        HostName
        NetAddress

Behavior      :
    - Existing signatures update LastSeen only.
    - FirstSeen is never modified after insertion.
    - New signatures are inserted with FirstSeen = LastSeen.
    - NULL values are compared explicitly.
    - Collection changes are performed in one transaction.
    - UPDLOCK and HOLDLOCK protect the insert existence check.
    - Existing historical records are never deleted.

Installation  :
    - Verifies that DBA.dbo.LoginActivity exists.
    - Skips creation if the SQL Server Agent job already exists.
    - Creates the job and collection step.
    - Creates a schedule running every minute.
    - Assigns the job to the local SQL Server instance.

Notes         :
    - Requires SQL Server Agent.
    - Job owner must exist and have sufficient permissions.
    - DMV access requires VIEW SERVER STATE on SQL Server 2012-2019.
    - On SQL Server 2022+, DMV permissions may require
      VIEW SERVER PERFORMANCE STATE.
    - The job records observed sessions, not every login event.
    - Short-lived connections between executions may be missed.
    - Data retention and cleanup are handled separately.
    - The DBA database is not automatically added to an AG.

===============================================================================
*/

USE [msdb];
GO

SET NOCOUNT ON;
GO

-------------------------------------------------------------------------------
-- 1. Validate DBA database and LoginActivity table
-------------------------------------------------------------------------------

IF OBJECT_ID(N'DBA.dbo.LoginActivity', N'U') IS NULL
BEGIN
    RAISERROR(
        'ERROR: Table [DBA].[dbo].[LoginActivity] does not exist.',
        16, 1
    );
    RETURN;
END;
GO

-------------------------------------------------------------------------------
-- 2. Create SQL Server Agent job if it does not already exist
-------------------------------------------------------------------------------

IF EXISTS
(
    SELECT 1
    FROM msdb.dbo.sysjobs
    WHERE name = N'DBA - Loginactivity'
)
BEGIN
    PRINT 'INFO: Job [DBA - Loginactivity] already exists.';
END
ELSE
BEGIN

    DECLARE
        @ReturnCode INT = 0,
        @JobID UNIQUEIDENTIFIER,
        @ScheduleID INT;

    BEGIN TRY

        BEGIN TRANSACTION;

        -----------------------------------------------------------------------
        -- 3. Create job
        -----------------------------------------------------------------------

        EXEC @ReturnCode = msdb.dbo.sp_add_job
            @job_name = N'DBA - Loginactivity',
            @enabled = 1,
            @description =
                N'Collects SQL Server user sessions every minute into '
                + N'DBA.dbo.LoginActivity. Updates LastSeen for existing '
                + N'signatures and inserts new signatures.',
            @category_name = N'[Uncategorized (Local)]',
            @owner_login_name = N'sa',
            @job_id = @JobID OUTPUT;

        IF @ReturnCode <> 0
            RAISERROR('Failed to create SQL Server Agent job.', 16, 1);

        -----------------------------------------------------------------------
        -- 4. Create collection step
        -----------------------------------------------------------------------

        EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
            @job_id = @JobID,
            @step_name = N'Get logins',
            @step_id = 1,
            @subsystem = N'TSQL',
            @database_name = N'DBA',
            @on_success_action = 1,
            @on_fail_action = 2,
            @command = N'
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Now DATETIME2(0) = SYSDATETIME();

---------------------------------------------------------------------------
-- 1. Collect current user sessions
---------------------------------------------------------------------------

SELECT DISTINCT
    CONVERT(SYSNAME, @@SERVERNAME) AS ServerName,
    s.original_login_name AS LoginName,
    DB_NAME(COALESCE(r.database_id, p.dbid)) AS DatabaseName,
    ag.name AS AGName,

    CONVERT(VARCHAR(20),
        CASE
            WHEN adc.group_id IS NULL THEN ''STANDALONE''
            ELSE COALESCE(ars.role_desc, ''UNKNOWN'')
        END
    ) AS ReplicaRole,

    CONVERT(NVARCHAR(128), s.program_name) AS Application,
    CONVERT(NVARCHAR(128), s.host_name) AS HostName,
    CONVERT(VARCHAR(48), c.client_net_address) AS NetAddress

INTO #Sessions

FROM sys.dm_exec_sessions AS s

LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id

LEFT JOIN sys.sysprocesses AS p
    ON p.spid = s.session_id

LEFT JOIN sys.dm_exec_connections AS c
    ON c.session_id = s.session_id

LEFT JOIN sys.databases AS d
    ON d.database_id = COALESCE(r.database_id, p.dbid)

LEFT JOIN sys.availability_databases_cluster AS adc
    ON adc.group_database_id = d.group_database_id

LEFT JOIN sys.availability_groups AS ag
    ON ag.group_id = adc.group_id

LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
    ON ars.group_id = adc.group_id
   AND ars.is_local = 1

WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
  AND s.original_login_name IS NOT NULL;

---------------------------------------------------------------------------
-- 2. Update existing session signatures
--    Only LastSeen is modified
---------------------------------------------------------------------------

BEGIN TRANSACTION;

UPDATE a
SET a.LastSeen = @Now

FROM dbo.LoginActivity AS a

INNER JOIN #Sessions AS s
    ON a.ServerName = s.ServerName
   AND a.LoginName = s.LoginName
   AND a.ReplicaRole = s.ReplicaRole

   AND (
        a.DatabaseName = s.DatabaseName
        OR (a.DatabaseName IS NULL AND s.DatabaseName IS NULL)
   )

   AND (
        a.AGName = s.AGName
        OR (a.AGName IS NULL AND s.AGName IS NULL)
   )

   AND (
        a.Application = s.Application
        OR (a.Application IS NULL AND s.Application IS NULL)
   )

   AND (
        a.HostName = s.HostName
        OR (a.HostName IS NULL AND s.HostName IS NULL)
   )

   AND (
        a.NetAddress = s.NetAddress
        OR (a.NetAddress IS NULL AND s.NetAddress IS NULL)
   );

---------------------------------------------------------------------------
-- 3. Insert new session signatures
---------------------------------------------------------------------------

INSERT INTO dbo.LoginActivity
(
    ServerName,
    LoginName,
    DatabaseName,
    AGName,
    ReplicaRole,
    Application,
    HostName,
    NetAddress,
    FirstSeen,
    LastSeen
)
SELECT
    s.ServerName,
    s.LoginName,
    s.DatabaseName,
    s.AGName,
    s.ReplicaRole,
    s.Application,
    s.HostName,
    s.NetAddress,
    @Now,
    @Now

FROM #Sessions AS s

WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.LoginActivity AS a WITH (UPDLOCK, HOLDLOCK)

    WHERE a.ServerName = s.ServerName
      AND a.LoginName = s.LoginName
      AND a.ReplicaRole = s.ReplicaRole

      AND (
            a.DatabaseName = s.DatabaseName
            OR (a.DatabaseName IS NULL AND s.DatabaseName IS NULL)
      )

      AND (
            a.AGName = s.AGName
            OR (a.AGName IS NULL AND s.AGName IS NULL)
      )

      AND (
            a.Application = s.Application
            OR (a.Application IS NULL AND s.Application IS NULL)
      )

      AND (
            a.HostName = s.HostName
            OR (a.HostName IS NULL AND s.HostName IS NULL)
      )

      AND (
            a.NetAddress = s.NetAddress
            OR (a.NetAddress IS NULL AND s.NetAddress IS NULL)
      )
);

COMMIT TRANSACTION;

DROP TABLE #Sessions;
',
            @retry_attempts = 0,
            @retry_interval = 0;

        IF @ReturnCode <> 0
            RAISERROR('Failed to create collection step.', 16, 1);

        -----------------------------------------------------------------------
        -- 5. Configure job start step
        -----------------------------------------------------------------------

        EXEC @ReturnCode = msdb.dbo.sp_update_job
            @job_id = @JobID,
            @start_step_id = 1;

        IF @ReturnCode <> 0
            RAISERROR('Failed to configure job start step.', 16, 1);

        -----------------------------------------------------------------------
        -- 6. Create schedule - every 1 minute
        -----------------------------------------------------------------------

        EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule
            @job_id = @JobID,
            @name = N'Every1min',
            @enabled = 1,
            @freq_type = 4,
            @freq_interval = 1,
            @freq_subday_type = 4,
            @freq_subday_interval = 1,
            @active_start_date = 20261026,
            @active_end_date = 99991231,
            @active_start_time = 0,
            @active_end_time = 235959,
            @schedule_id = @ScheduleID OUTPUT;

        IF @ReturnCode <> 0
            RAISERROR('Failed to create job schedule.', 16, 1);

        -----------------------------------------------------------------------
        -- 7. Assign job to local SQL Server instance
        -----------------------------------------------------------------------

        EXEC @ReturnCode = msdb.dbo.sp_add_jobserver
            @job_id = @JobID,
            @server_name = N'(local)';

        IF @ReturnCode <> 0
            RAISERROR('Failed to assign job to local server.', 16, 1);

        COMMIT TRANSACTION;

        PRINT 'SUCCESS: Job [DBA - Loginactivity] created.';
        PRINT 'SUCCESS: Schedule configured for every 1 minute.';

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT 'ERROR: Job creation failed.';
        THROW;

    END CATCH;

END;
GO
