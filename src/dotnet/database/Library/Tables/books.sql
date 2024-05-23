CREATE TABLE [dbo].[books] (
    [id]    INT             DEFAULT (NEXT VALUE FOR [dbo].[globalId]) NOT NULL,
    [title] NVARCHAR (1000) NOT NULL,
    [year]  INT             NULL,
    [pages] INT             NULL,
    PRIMARY KEY CLUSTERED ([id] ASC)
);


GO

