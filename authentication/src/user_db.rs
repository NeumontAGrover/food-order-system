use tokio_postgres::NoTls;

pub async fn connect() -> Result<(), tokio_postgres::Error> {
    let (client, connection) =
        tokio_postgres::connect("host=localhost user=foodguy", NoTls).await?;
    
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("Could not connect to PostgreSQL: {}", e);
        }
    });

    Ok(())
}
