CREATE TABLE [dbo].[books_authors] (
    [author_id] INT NOT NULL,
    [book_id]   INT NOT NULL,
    PRIMARY KEY CLUSTERED ([author_id] ASC, [book_id] ASC),
    FOREIGN KEY ([author_id]) REFERENCES [dbo].[authors] ([id]),
    FOREIGN KEY ([book_id]) REFERENCES [dbo].[books] ([id])
);


GO

CREATE NONCLUSTERED INDEX [ixnc1]
    ON [dbo].[books_authors]([book_id] ASC, [author_id] ASC);


GO

