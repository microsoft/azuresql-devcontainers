
create   view dbo.vw_books_details
as
    with
        aggregated_authors
        as
        (
            select
                ba.book_id,
                string_agg(concat(a.first_name, ' ', (a.middle_name + ' '), a.last_name), ', ') as authors
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

GO

