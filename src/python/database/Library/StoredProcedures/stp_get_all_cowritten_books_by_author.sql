
create   procedure dbo.stp_get_all_cowritten_books_by_author
    @author nvarchar(100),
    @searchType char(1) = 'c'
as

declare @authorSearchString nvarchar(110);

if @searchType = 'c' 
    set @authorSearchString = '%' + @author + '%' -- contains
else if @searchType = 's' 
    set @authorSearchString = @author + '%' -- startswith
else 
    throw 50000, '@searchType must be set to "c" or "s"', 16;

with
    aggregated_authors
    as
    (
        select
            ba.book_id,
            string_agg(concat(a.first_name, ' ', (a.middle_name + ' '), a.last_name), ', ') as authors,
            author_count = count(*)
        from
            dbo.books_authors ba
            inner join
            dbo.authors a on ba.author_id = a.id
        group by
        ba.book_id
    )
select
    b.id,
    b.title,
    b.pages,
    b.[year],
    aa.authors
from
    dbo.books b
    inner join
    aggregated_authors aa on b.id = aa.book_id
    inner join
    dbo.books_authors ba on b.id = ba.book_id
    inner join
    dbo.authors a on a.id = ba.author_id
where
    aa.author_count > 1
    and
    (
        concat(a.first_name, ' ', (a.middle_name + ' '), a.last_name) like @authorSearchString
    or
    concat(a.first_name, ' ', a.last_name) like @authorSearchString
);

GO

