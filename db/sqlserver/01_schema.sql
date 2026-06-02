-- ============================================================
-- QualityDMS - Script de Base de Datos SQL Server
-- GENERADO DIRECTAMENTE POR: dotnet ef dbcontext script
-- Fuente de verdad: EF Core 10.0.4 + Identity 10.0.4
-- NO editar manualmente - regenerar con: dotnet ef dbcontext script
--
-- ADVERTENCIA: Este script es para instalación limpia (desarrollo/CI).
-- En PRODUCCIÓN comentar el bloque DROP DATABASE de abajo.
-- En producción usar: dotnet ef database update
-- ============================================================

USE master;
GO

-- ⚠️  SOLO PARA ENTORNO DE DESARROLLO — comentar en producción
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'QualityDMS')
BEGIN
    ALTER DATABASE [QualityDMS] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [QualityDMS];
END
GO

CREATE DATABASE [QualityDMS] COLLATE Latin1_General_CI_AS;
GO

USE [QualityDMS];
GO

-- ============================================================

CREATE TABLE [AspNetRoles] (
    [Id] nvarchar(450) NOT NULL,
    [Name] nvarchar(256) NULL,
    [NormalizedName] nvarchar(256) NULL,
    [ConcurrencyStamp] nvarchar(max) NULL,
    CONSTRAINT [PK_AspNetRoles] PRIMARY KEY ([Id])
);
GO

CREATE TABLE [Companies] (
    [CompanyId] int NOT NULL IDENTITY,
    [Code] nvarchar(20) NOT NULL,
    [Name] nvarchar(200) NOT NULL,
    [TaxId] nvarchar(max) NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_Companies] PRIMARY KEY ([CompanyId])
);
GO

CREATE TABLE [AspNetUsers] (
    [Id] nvarchar(450) NOT NULL,
    [FirstName] nvarchar(max) NOT NULL,
    [LastName] nvarchar(max) NOT NULL,
    [CompanyId] int NULL,
    [DepartmentId] int NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [UserName] nvarchar(256) NULL,
    [NormalizedUserName] nvarchar(256) NULL,
    [Email] nvarchar(256) NULL,
    [NormalizedEmail] nvarchar(256) NULL,
    [EmailConfirmed] bit NOT NULL,
    [PasswordHash] nvarchar(max) NULL,
    [SecurityStamp] nvarchar(max) NULL,
    [ConcurrencyStamp] nvarchar(max) NULL,
    [PhoneNumber] nvarchar(max) NULL,
    [PhoneNumberConfirmed] bit NOT NULL,
    [TwoFactorEnabled] bit NOT NULL,
    [LockoutEnd] datetimeoffset NULL,
    [LockoutEnabled] bit NOT NULL,
    [AccessFailedCount] int NOT NULL,
    CONSTRAINT [PK_AspNetUsers] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_AspNetUsers_Companies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [Companies] ([CompanyId]) ON DELETE NO ACTION
);
GO

CREATE TABLE [AuditLogs] (
    [AuditLogId] bigint NOT NULL IDENTITY,
    [UserId] nvarchar(450) NOT NULL,
    [Action] nvarchar(100) NOT NULL,
    [EntityName] nvarchar(100) NOT NULL,
    [EntityId] nvarchar(100) NULL,
    [OldValues] nvarchar(max) NULL,
    [NewValues] nvarchar(max) NULL,
    [IpAddress] nvarchar(45) NULL,
    [Timestamp] datetime2 NOT NULL,
    CONSTRAINT [PK_AuditLogs] PRIMARY KEY ([AuditLogId])
);
GO

CREATE TABLE [Departments] (
    [DepartmentId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [Code] nvarchar(20) NOT NULL,
    [Name] nvarchar(150) NOT NULL,
    [Description] nvarchar(500) NULL,
    [ManagerName] nvarchar(200) NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_Departments] PRIMARY KEY ([DepartmentId]),
    CONSTRAINT [FK_Departments_Companies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [Companies] ([CompanyId]) ON DELETE NO ACTION
);
GO

CREATE TABLE [DocumentCategories] (
    [CategoryId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [Code] nvarchar(20) NOT NULL,
    [Name] nvarchar(150) NOT NULL,
    [Description] nvarchar(500) NULL,
    [ParentCategoryId] int NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_DocumentCategories] PRIMARY KEY ([CategoryId]),
    CONSTRAINT [FK_DocumentCategories_Companies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [Companies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_DocumentCategories_DocumentCategories_ParentCategoryId] FOREIGN KEY ([ParentCategoryId]) REFERENCES [DocumentCategories] ([CategoryId]) ON DELETE NO ACTION
);
GO

CREATE TABLE [Notifications] (
    [NotificationId] int NOT NULL IDENTITY,
    [RecipientUserId] nvarchar(450) NOT NULL,
    [Type] nvarchar(50) NOT NULL,
    [Title] nvarchar(300) NOT NULL,
    [Message] nvarchar(2000) NOT NULL,
    [RelatedDocumentId] int NULL,
    [IsRead] bit NOT NULL,
    [ReadAt] datetime2 NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_Notifications] PRIMARY KEY ([NotificationId])
);
GO

CREATE TABLE [WorkflowTemplates] (
    [WorkflowTemplateId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [Name] nvarchar(200) NOT NULL,
    [Description] nvarchar(500) NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_WorkflowTemplates] PRIMARY KEY ([WorkflowTemplateId]),
    CONSTRAINT [FK_WorkflowTemplates_Companies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [Companies] ([CompanyId]) ON DELETE NO ACTION
);
GO

CREATE TABLE [AspNetRoleClaims] (
    [Id] int NOT NULL IDENTITY,
    [RoleId] nvarchar(450) NOT NULL,
    [ClaimType] nvarchar(max) NULL,
    [ClaimValue] nvarchar(max) NULL,
    CONSTRAINT [PK_AspNetRoleClaims] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_AspNetRoleClaims_AspNetRoles_RoleId] FOREIGN KEY ([RoleId]) REFERENCES [AspNetRoles] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [AspNetUserClaims] (
    [Id] int NOT NULL IDENTITY,
    [UserId] nvarchar(450) NOT NULL,
    [ClaimType] nvarchar(max) NULL,
    [ClaimValue] nvarchar(max) NULL,
    CONSTRAINT [PK_AspNetUserClaims] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_AspNetUserClaims_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [AspNetUserLogins] (
    [LoginProvider] nvarchar(450) NOT NULL,
    [ProviderKey] nvarchar(450) NOT NULL,
    [ProviderDisplayName] nvarchar(max) NULL,
    [UserId] nvarchar(450) NOT NULL,
    CONSTRAINT [PK_AspNetUserLogins] PRIMARY KEY ([LoginProvider], [ProviderKey]),
    CONSTRAINT [FK_AspNetUserLogins_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [AspNetUserRoles] (
    [UserId] nvarchar(450) NOT NULL,
    [RoleId] nvarchar(450) NOT NULL,
    CONSTRAINT [PK_AspNetUserRoles] PRIMARY KEY ([UserId], [RoleId]),
    CONSTRAINT [FK_AspNetUserRoles_AspNetRoles_RoleId] FOREIGN KEY ([RoleId]) REFERENCES [AspNetRoles] ([Id]) ON DELETE CASCADE,
    CONSTRAINT [FK_AspNetUserRoles_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [AspNetUserTokens] (
    [UserId] nvarchar(450) NOT NULL,
    [LoginProvider] nvarchar(450) NOT NULL,
    [Name] nvarchar(450) NOT NULL,
    [Value] nvarchar(max) NULL,
    CONSTRAINT [PK_AspNetUserTokens] PRIMARY KEY ([UserId], [LoginProvider], [Name]),
    CONSTRAINT [FK_AspNetUserTokens_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [QualityAudits] (
    [AuditId] int NOT NULL IDENTITY,
    [AuditCode] nvarchar(50) NOT NULL,
    [Title] nvarchar(300) NOT NULL,
    [Description] nvarchar(2000) NULL,
    [DepartmentId] int NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [PlannedDate] datetime2 NOT NULL,
    [ExecutedDate] datetime2 NULL,
    [ClosedDate] datetime2 NULL,
    [AuditorUserId] nvarchar(450) NULL,
    [Summary] nvarchar(4000) NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_QualityAudits] PRIMARY KEY ([AuditId]),
    CONSTRAINT [FK_QualityAudits_Departments_DepartmentId] FOREIGN KEY ([DepartmentId]) REFERENCES [Departments] ([DepartmentId]) ON DELETE CASCADE
);
GO

CREATE TABLE [Documents] (
    [DocumentId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [Code] nvarchar(50) NOT NULL,
    [Title] nvarchar(500) NOT NULL,
    [Description] nvarchar(2000) NULL,
    [CurrentStatus] int NOT NULL,
    [CategoryId] int NOT NULL,
    [DepartmentId] int NOT NULL,
    [WorkflowTemplateId] int NULL,
    [EffectiveDate] datetime2 NULL,
    [ExpirationDate] datetime2 NULL,
    [NextReviewDate] datetime2 NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(450) NULL,
    CONSTRAINT [PK_Documents] PRIMARY KEY ([DocumentId]),
    CONSTRAINT [FK_Documents_Companies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [Companies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Documents_Departments_DepartmentId] FOREIGN KEY ([DepartmentId]) REFERENCES [Departments] ([DepartmentId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Documents_DocumentCategories_CategoryId] FOREIGN KEY ([CategoryId]) REFERENCES [DocumentCategories] ([CategoryId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Documents_WorkflowTemplates_WorkflowTemplateId] FOREIGN KEY ([WorkflowTemplateId]) REFERENCES [WorkflowTemplates] ([WorkflowTemplateId])
);
GO

CREATE TABLE [WorkflowSteps] (
    [WorkflowStepId] int NOT NULL IDENTITY,
    [WorkflowTemplateId] int NOT NULL,
    [StepOrder] int NOT NULL,
    [StepName] nvarchar(200) NOT NULL,
    [Description] nvarchar(500) NULL,
    [AssignedRoleName] nvarchar(100) NULL,
    [AssignedUserId] nvarchar(450) NULL,
    [RequiresAllApprovers] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_WorkflowSteps] PRIMARY KEY ([WorkflowStepId]),
    CONSTRAINT [FK_WorkflowSteps_WorkflowTemplates_WorkflowTemplateId] FOREIGN KEY ([WorkflowTemplateId]) REFERENCES [WorkflowTemplates] ([WorkflowTemplateId]) ON DELETE CASCADE
);
GO

CREATE TABLE [AuditFindings] (
    [FindingId] int NOT NULL IDENTITY,
    [AuditId] int NOT NULL,
    [Description] nvarchar(2000) NOT NULL,
    [FindingType] nvarchar(50) NOT NULL,
    [CorrectiveAction] nvarchar(2000) NULL,
    [DueDate] datetime2 NULL,
    [IsClosed] bit NOT NULL,
    [ClosedDate] datetime2 NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_AuditFindings] PRIMARY KEY ([FindingId]),
    CONSTRAINT [FK_AuditFindings_QualityAudits_AuditId] FOREIGN KEY ([AuditId]) REFERENCES [QualityAudits] ([AuditId]) ON DELETE CASCADE
);
GO

CREATE TABLE [ControlledDistributions] (
    [DistributionId] int NOT NULL IDENTITY,
    [DocumentId] int NOT NULL,
    [RecipientUserId] nvarchar(450) NOT NULL,
    [RecipientName] nvarchar(200) NULL,
    [SentAt] datetime2 NOT NULL,
    [AcknowledgedAt] datetime2 NULL,
    [IsAcknowledged] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_ControlledDistributions] PRIMARY KEY ([DistributionId]),
    CONSTRAINT [FK_ControlledDistributions_Documents_DocumentId] FOREIGN KEY ([DocumentId]) REFERENCES [Documents] ([DocumentId]) ON DELETE CASCADE
);
GO

CREATE TABLE [DocumentVersions] (
    [VersionId] int NOT NULL IDENTITY,
    [DocumentId] int NOT NULL,
    [VersionNumber] nvarchar(20) NOT NULL,
    [FilePath] nvarchar(1000) NOT NULL,
    [FileName] nvarchar(255) NULL,
    [FileSizeBytes] bigint NOT NULL,
    [ContentType] nvarchar(100) NULL,
    [ChangeLog] nvarchar(2000) NULL,
    [IsCurrent] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_DocumentVersions] PRIMARY KEY ([VersionId]),
    CONSTRAINT [FK_DocumentVersions_Documents_DocumentId] FOREIGN KEY ([DocumentId]) REFERENCES [Documents] ([DocumentId]) ON DELETE CASCADE
);
GO

CREATE TABLE [WorkflowInstances] (
    [WorkflowInstanceId] int NOT NULL IDENTITY,
    [DocumentId] int NOT NULL,
    [WorkflowTemplateId] int NOT NULL,
    [CurrentStepOrder] int NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [CompletedAt] datetime2 NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_WorkflowInstances] PRIMARY KEY ([WorkflowInstanceId]),
    CONSTRAINT [FK_WorkflowInstances_Documents_DocumentId] FOREIGN KEY ([DocumentId]) REFERENCES [Documents] ([DocumentId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_WorkflowInstances_WorkflowTemplates_WorkflowTemplateId] FOREIGN KEY ([WorkflowTemplateId]) REFERENCES [WorkflowTemplates] ([WorkflowTemplateId]) ON DELETE CASCADE
);
GO

CREATE TABLE [WorkflowActions] (
    [WorkflowActionId] int NOT NULL IDENTITY,
    [WorkflowInstanceId] int NOT NULL,
    [StepOrder] int NOT NULL,
    [ActionByUserId] nvarchar(450) NOT NULL,
    [Action] nvarchar(30) NOT NULL,
    [Comments] nvarchar(1000) NULL,
    [ActionDate] datetime2 NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(450) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NULL,
    CONSTRAINT [PK_WorkflowActions] PRIMARY KEY ([WorkflowActionId]),
    CONSTRAINT [FK_WorkflowActions_WorkflowInstances_WorkflowInstanceId] FOREIGN KEY ([WorkflowInstanceId]) REFERENCES [WorkflowInstances] ([WorkflowInstanceId]) ON DELETE CASCADE
);
GO

-- ============================================================
-- INDICES
-- ============================================================

CREATE INDEX [IX_AspNetRoleClaims_RoleId] ON [AspNetRoleClaims] ([RoleId]);
GO

CREATE UNIQUE INDEX [RoleNameIndex] ON [AspNetRoles] ([NormalizedName]) WHERE [NormalizedName] IS NOT NULL;
GO

CREATE INDEX [IX_AspNetUserClaims_UserId] ON [AspNetUserClaims] ([UserId]);
GO

CREATE INDEX [IX_AspNetUserLogins_UserId] ON [AspNetUserLogins] ([UserId]);
GO

CREATE INDEX [IX_AspNetUserRoles_RoleId] ON [AspNetUserRoles] ([RoleId]);
GO

CREATE INDEX [EmailIndex] ON [AspNetUsers] ([NormalizedEmail]);
GO

CREATE UNIQUE INDEX [UserNameIndex] ON [AspNetUsers] ([NormalizedUserName]) WHERE [NormalizedUserName] IS NOT NULL;
GO

CREATE INDEX [IX_AuditFindings_AuditId] ON [AuditFindings] ([AuditId]);
GO

CREATE INDEX [IX_AuditFindings_IsClosed] ON [AuditFindings] ([IsClosed]);
GO

CREATE INDEX [IX_AuditLogs_EntityName_EntityId] ON [AuditLogs] ([EntityName], [EntityId]);
GO

CREATE INDEX [IX_AuditLogs_Timestamp] ON [AuditLogs] ([Timestamp]);
GO

CREATE INDEX [IX_AuditLogs_UserId] ON [AuditLogs] ([UserId]);
GO

CREATE INDEX [IX_ControlledDistributions_DocumentId] ON [ControlledDistributions] ([DocumentId]);
GO

CREATE INDEX [IX_ControlledDistributions_RecipientUserId] ON [ControlledDistributions] ([RecipientUserId]);
GO

CREATE UNIQUE INDEX [IX_Companies_Code] ON [Companies] ([Code]);
GO

CREATE INDEX [IX_AspNetUsers_CompanyId] ON [AspNetUsers] ([CompanyId]);
GO

CREATE UNIQUE INDEX [IX_Departments_CompanyId_Code] ON [Departments] ([CompanyId], [Code]);
GO

CREATE INDEX [IX_Departments_CompanyId] ON [Departments] ([CompanyId]);
GO

CREATE UNIQUE INDEX [IX_DocumentCategories_CompanyId_Code] ON [DocumentCategories] ([CompanyId], [Code]);
GO

CREATE INDEX [IX_DocumentCategories_ParentCategoryId] ON [DocumentCategories] ([ParentCategoryId]);
GO

CREATE INDEX [IX_Documents_CategoryId] ON [Documents] ([CategoryId]);
GO

CREATE INDEX [IX_DocumentCategories_CompanyId] ON [DocumentCategories] ([CompanyId]);
GO

CREATE INDEX [IX_WorkflowTemplates_CompanyId] ON [WorkflowTemplates] ([CompanyId]);
GO

CREATE UNIQUE INDEX [IX_Documents_CompanyId_Code] ON [Documents] ([CompanyId], [Code]);
GO

CREATE INDEX [IX_Documents_CompanyId] ON [Documents] ([CompanyId]);
GO

CREATE INDEX [IX_Documents_DepartmentId] ON [Documents] ([DepartmentId]);
GO

CREATE INDEX [IX_Documents_NextReviewDate] ON [Documents] ([NextReviewDate]);
GO

CREATE INDEX [IX_Documents_WorkflowTemplateId] ON [Documents] ([WorkflowTemplateId]);
GO

CREATE UNIQUE INDEX [IX_DocumentVersions_DocumentId_VersionNumber] ON [DocumentVersions] ([DocumentId], [VersionNumber]);
GO

CREATE INDEX [IX_DocumentVersions_IsCurrent] ON [DocumentVersions] ([IsCurrent]);
GO

CREATE INDEX [IX_Notifications_IsRead] ON [Notifications] ([IsRead]);
GO

CREATE INDEX [IX_Notifications_RecipientUserId] ON [Notifications] ([RecipientUserId]);
GO

CREATE UNIQUE INDEX [IX_QualityAudits_AuditCode] ON [QualityAudits] ([AuditCode]);
GO

CREATE INDEX [IX_QualityAudits_DepartmentId] ON [QualityAudits] ([DepartmentId]);
GO

CREATE INDEX [IX_QualityAudits_Status] ON [QualityAudits] ([Status]);
GO

CREATE INDEX [IX_WorkflowActions_ActionByUserId] ON [WorkflowActions] ([ActionByUserId]);
GO

CREATE INDEX [IX_WorkflowActions_WorkflowInstanceId] ON [WorkflowActions] ([WorkflowInstanceId]);
GO

CREATE INDEX [IX_WorkflowInstances_DocumentId_Status] ON [WorkflowInstances] ([DocumentId], [Status]);
GO

CREATE INDEX [IX_WorkflowInstances_WorkflowTemplateId] ON [WorkflowInstances] ([WorkflowTemplateId]);
GO

CREATE UNIQUE INDEX [IX_WorkflowSteps_WorkflowTemplateId_StepOrder] ON [WorkflowSteps] ([WorkflowTemplateId], [StepOrder]);
GO

PRINT 'QualityDMS schema creado exitosamente.';
GO
