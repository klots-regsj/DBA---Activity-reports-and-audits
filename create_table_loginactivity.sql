
/*
===============================================================================
DBA - LOGIN ACTIVITY TABLE - VERSION 1.0
===============================================================================
Name          : 2.sql.dba.login_activity
Purpose       : Create the LoginActivity table used to track observed SQL
                Server login sessions and database access over time.

Database      : DBA
Schema        : dbo
Object        : dbo.LoginActivity
Type          : Table

Compatibility : SQL Server 2012+
AG Handling   : Supports both standalone SQL Server instances and
                Always On Availability Groups.
                AGName and ReplicaRole are populated by the collection job.

Collection    : External SQL Server Agent job (typically every 1 minute).

Behavior      :
    - Stores the SQL Server instance name.
    - Records login and database information.
    - Records AG name and replica role.
    - Records application, client hostname and network address.
    - FirstSeen identifies when a session signature was first observed.
    - LastSeen identifies when the signature was last observed.
    - Repeated observations should update LastSeen only.
    - New session signatures should create new records.

Columns       :
    ID          : Unique identity for each activity record.
    ServerName  : SQL Server instance name.
    LoginName   : SQL Server or Windows login.
    DatabaseName: Database associated with the session.
    AGName      : Availability Group name, if applicable.
    ReplicaRole : PRIMARY, SECONDARY or STANDALONE.
    Application : Client application name.
    HostName    : Client computer name.
    NetAddress  : Client IP address.
    FirstSeen   : First observed activity.
    LastSeen    : Most recent observed activity.

Notes         :
    - Table creation is skipped if the table already exists.
    - No existing records are modified or deleted.
    - FirstSeen and LastSeen default to SYSDATETIME().
    - Session signature matching is handled by the collection job.
    - This table records observed sessions, not every individual login.
    - Data retention and cleanup must be handled separately.

===============================================================================
*/

USE [DBA];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
GO

-------------------------------------------------------------------------------
-- 1. Create LoginActivity table if it does not already exist
-------------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.LoginActivity', N'U') IS NULL
BEGIN

    CREATE TABLE [dbo].[LoginActivity]
    (
        [ID]           BIGINT IDENTITY(1,1) NOT NULL,
        [ServerName]   SYSNAME NOT NULL,
        [LoginName]    SYSNAME NOT NULL,
        [DatabaseName] SYSNAME NULL,
        [AGName]       SYSNAME NULL,
        [ReplicaRole]  VARCHAR(20) NOT NULL,
        [Application]  NVARCHAR(128) NULL,
        [HostName]     NVARCHAR(128) NULL,
        [NetAddress]   VARCHAR(48) NULL,
        [FirstSeen]    DATETIME2(0) NOT NULL
            CONSTRAINT [DF_LoginActivity_FirstSeen]
            DEFAULT (SYSDATETIME()),
        [LastSeen]     DATETIME2(0) NOT NULL
            CONSTRAINT [DF_LoginActivity_LastSeen]
            DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_LoginActivity]
            PRIMARY KEY CLUSTERED
            (
                [ID] ASC
            )
            WITH
            (
                PAD_INDEX = OFF,
                STATISTICS_NORECOMPUTE = OFF,
                IGNORE_DUP_KEY = OFF,
                ALLOW_ROW_LOCKS = ON,
                ALLOW_PAGE_LOCKS = ON,
                FILLFACTOR = 100
            )
            ON [PRIMARY]
    )
    ON [PRIMARY];

    PRINT 'SUCCESS: Table [DBA].[dbo].[LoginActivity] created.';

END
ELSE
BEGIN

    PRINT 'INFO: Table [DBA].[dbo].[LoginActivity] already exists.';

END;
GO
