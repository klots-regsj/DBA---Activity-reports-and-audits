
/*
===============================================================================
DBA - LOGIN ACTIVITY INDEXES - VERSION 1.0
===============================================================================
Name          : create_index_loginactivity.sql
Purpose       : Create supporting indexes for the LoginActivity table
                to improve session signature matching, activity reporting
                and retention queries.

Database      : DBA
Schema        : dbo
Object        : dbo.LoginActivity
Type          : Nonclustered Indexes

Compatibility : SQL Server 2012+
AG Handling   : Supports both standalone SQL Server instances and
                Always On Availability Groups.
                Indexes are created locally on the DBA database.

Indexes       :
    IX_LoginActivity_Signature
        Supports matching existing session signatures using:
        ServerName, LoginName, DatabaseName, AGName, ReplicaRole,
        Application, HostName and NetAddress.

    IX_LoginActivity_LastSeen
        Supports filtering and ordering by LastSeen.
        Includes FirstSeen for activity reporting.

Behavior      :
    - Verifies that dbo.LoginActivity exists.
    - Checks whether each index already exists.
    - Creates only missing indexes.
    - Does not modify or delete existing records.
    - Can safely be executed multiple times.

Notes         :
    - Designed for collection jobs running approximately every minute.
    - Signature matching must handle nullable columns correctly.
    - The signature index is non-unique to preserve existing behavior.
    - Index maintenance is handled separately.
    - Additional indexes increase storage and write overhead.
    - Existing indexes are not rebuilt or modified.

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
-- 1. Validate LoginActivity table
-------------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.LoginActivity', N'U') IS NULL
BEGIN
    RAISERROR(
        'ERROR: Table [DBA].[dbo].[LoginActivity] does not exist.',
        16, 1
    );
END
ELSE
BEGIN

    ---------------------------------------------------------------------------
    -- 2. Create index for session signature matching
    ---------------------------------------------------------------------------

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.LoginActivity')
          AND name = N'IX_LoginActivity_Signature'
    )
    BEGIN

        CREATE NONCLUSTERED INDEX [IX_LoginActivity_Signature]
        ON [dbo].[LoginActivity]
        (
            [ServerName] ASC,
            [LoginName] ASC,
            [DatabaseName] ASC,
            [AGName] ASC,
            [ReplicaRole] ASC,
            [Application] ASC,
            [HostName] ASC,
            [NetAddress] ASC
        )
        WITH
        (
            PAD_INDEX = OFF,
            STATISTICS_NORECOMPUTE = OFF,
            SORT_IN_TEMPDB = OFF,
            IGNORE_DUP_KEY = OFF,
            ALLOW_ROW_LOCKS = ON,
            ALLOW_PAGE_LOCKS = ON,
            FILLFACTOR = 100
        )
        ON [PRIMARY];

        PRINT 'SUCCESS: Index IX_LoginActivity_Signature created.';

    END
    ELSE
    BEGIN

        PRINT 'INFO: Index IX_LoginActivity_Signature already exists.';

    END;

    ---------------------------------------------------------------------------
    -- 3. Create index for LastSeen reporting and retention
    ---------------------------------------------------------------------------

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.LoginActivity')
          AND name = N'IX_LoginActivity_LastSeen'
    )
    BEGIN

        CREATE NONCLUSTERED INDEX [IX_LoginActivity_LastSeen]
        ON [dbo].[LoginActivity]
        (
            [LastSeen] ASC
        )
        INCLUDE
        (
            [FirstSeen]
        )
        WITH
        (
            PAD_INDEX = OFF,
            STATISTICS_NORECOMPUTE = OFF,
            SORT_IN_TEMPDB = OFF,
            IGNORE_DUP_KEY = OFF,
            ALLOW_ROW_LOCKS = ON,
            ALLOW_PAGE_LOCKS = ON,
            FILLFACTOR = 100
        )
        ON [PRIMARY];

        PRINT 'SUCCESS: Index IX_LoginActivity_LastSeen created.';

    END
    ELSE
    BEGIN

        PRINT 'INFO: Index IX_LoginActivity_LastSeen already exists.';

    END;

END;
GO
