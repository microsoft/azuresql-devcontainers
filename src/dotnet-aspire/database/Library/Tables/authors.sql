CREATE TABLE [dbo].[authors] (
    [id]          INT            DEFAULT (NEXT VALUE FOR [dbo].[globalId]) NOT NULL,
    [first_name]  NVARCHAR (100) NOT NULL,
    [middle_name] NVARCHAR (100) NULL,
    [last_name]   NVARCHAR (100) NOT NULL,
    PRIMARY KEY CLUSTERED ([id] ASC)
);


GO

