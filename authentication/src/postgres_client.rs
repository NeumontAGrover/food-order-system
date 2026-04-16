use tokio_postgres::{Client, Error, NoTls};

pub struct PostgresClient {
    client: Client,
}

impl PostgresClient {
    pub async fn new() -> Result<PostgresClient, Error> {
        let config = "host=postgresdb user=foodguy password=foodServiceDB port=5432";
        let (client, connection) =
            tokio_postgres::connect(config, NoTls).await?;
    
        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("Could not connect to PostgreSQL: {}", e);
            } else {
                println!("Connected to Postgres")
            }
        });

        Ok(PostgresClient { client: client })
    }

    pub async fn create_tables(&self) -> Result<u64, Error> {
        let sql_statement = "CREATE TABLE IF NOT EXISTS users(
            uid SERIAL PRIMARY KEY NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL
        )";
        self.client.execute(sql_statement, &[]).await
    }

    pub async fn add_user(&self, username: &str, password: &str) -> Result<u64, Error> {
        println!("Adding {} to database", username);
        let sql_statement = "INSERT INTO users(username, password) VALUES($1::TEXT, $2::TEXT)";
        self.client.execute(sql_statement, &[&username, &password]).await
    }
}
