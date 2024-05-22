-- This file contains SQL statements that will be executed after the build script.
-- Authors data
---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.authors WHERE id = 1)
BEGIN
    INSERT INTO dbo.authors (id, first_name, middle_name, last_name)
    VALUES (1, 'Isaac', 'Yudovick', 'Asimov')
END;

IF NOT EXISTS (SELECT 1 FROM dbo.authors WHERE id = 2)
BEGIN
    INSERT INTO dbo.authors (id, first_name, middle_name, last_name)
    VALUES (2, 'Arthur', 'Charles', 'Clarke')
END;

IF NOT EXISTS (SELECT 1 FROM dbo.authors WHERE id = 3)
BEGIN
    INSERT INTO dbo.authors (id, first_name, middle_name, last_name)
    VALUES (3, 'Herbert', 'George', 'Wells')
END;

IF NOT EXISTS (SELECT 1 FROM dbo.authors WHERE id = 4)
BEGIN
    INSERT INTO dbo.authors (id, first_name, middle_name, last_name)
    VALUES (4, 'Jules', 'Gabriel', 'Verne')
END;

IF NOT EXISTS (SELECT 1 FROM dbo.authors WHERE id = 5)
BEGIN
    INSERT INTO dbo.authors (id, first_name, middle_name, last_name)
    VALUES (5, 'Philip', 'Kindred', 'Dick')
END;
GO

-- Books data
---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1000)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1000, 'Prelude to Foundation', 1988, 403)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1001)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1001, 'Forward the Foundation', 1993, 417)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1002)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1002, 'Foundation', 1951, 255)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1003)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1003, 'Foundation and Empire', 1952, 247)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1004)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1004, 'Second Foundation', 1953, 210)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1005)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1005, 'Foundation''s Edge', 1982, 367)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1006)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1006, 'Foundation and Earth', 1986, 356)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1007)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1007, 'Nemesis', 1989, 386)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1008)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1008, '2001: A Space Odyssey', 1968, 221)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1009)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1009, '2010: Odyssey Two', 1982, 291)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1010)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1010, '2061: Odyssey Three ', 1987, 256)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1011)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1011, '3001: The Final Odyssey ', 1997, 288)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1012)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1012, 'The Time Machine', 1895, 118)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1013)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1013, 'The Island of Doctor Moreau', 1896, 153)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1014)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1014, 'The Invisible Man', 1897, 151)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1015)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1015, 'The War of the Worlds', 1898, 192)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1016)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1016, 'Journey to the Center of the Earth', 1864, 183)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1017)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1017, 'Twenty Thousand Leagues Under the Sea', 1870, 187)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1018)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1018, 'Around the World in Eighty Days', 1873, 167)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1019)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1019, 'From the Earth to the Moon', 1865, 186)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1020)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1020, 'Do Androids Dream of Electric Sheep?', 1968, 244)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1021)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1021, 'Ubik', 1969, 224)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1022)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1022, 'The Man in the High Castle', 1962, 259)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books WHERE id = 1023)
BEGIN
    INSERT INTO dbo.books (id, title, year, pages)
    VALUES (1023, 'A Scanner Darkly', 1977, 224)
END;
GO

-- Books + Authors data
---------------------------------------------------------------------------
-- Insert records for author 1
IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1000)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1000)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1001)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1001)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1002)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1002)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1003)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1003)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1004)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1004)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1005)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1005)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1006)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1006)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 1 AND book_id = 1007)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (1, 1007)
END;

-- Insert records for author 2
IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 2 AND book_id = 1008)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (2, 1008)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 2 AND book_id = 1009)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (2, 1009)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 2 AND book_id = 1010)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (2, 1010)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 2 AND book_id = 1011)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (2, 1011)
END;

-- Insert records for author 3
IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 3 AND book_id = 1012)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (3, 1012)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 3 AND book_id = 1013)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (3, 1013)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 3 AND book_id = 1014)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (3, 1014)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 3 AND book_id = 1015)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (3, 1015)
END;

-- Insert records for author 4
IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 4 AND book_id = 1016)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (4, 1016)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 4 AND book_id = 1017)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (4, 1017)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 4 AND book_id = 1018)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (4, 1018)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 4 AND book_id = 1019)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (4, 1019)
END;

-- Insert records for author 5
IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 5 AND book_id = 1020)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (5, 1020)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 5 AND book_id = 1021)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (5, 1021)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 5 AND book_id = 1022)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (5, 1022)
END;

IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 5 AND book_id = 1023)
BEGIN
    INSERT INTO dbo.books_authors (author_id, book_id)
    VALUES (5, 1023)
END;
GO