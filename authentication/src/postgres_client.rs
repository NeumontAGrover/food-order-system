use serde::Serialize;
use tokio_postgres::{Client, Error, NoTls};

#[derive(Serialize)]
pub struct User {
    pub username: String,
    pub first_name: String,
    pub last_name: String,
    pub admin: bool,
}

impl User {
    pub fn new() -> User {
        User {
            username: String::from(""),
            first_name: String::from(""),
            last_name: String::from(""),
            admin: false
        }
    }
}

pub struct PostgresClient {
    client: Client,
    next_uid: i32,
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

        Ok(PostgresClient { client: client, next_uid: 0 })
    }

    pub async fn setup_client(&mut self) -> Result<(), Error> {
        let sql_statement = "CREATE TABLE IF NOT EXISTS users(
            uid INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            first_name TEXT NOT NULL,
            last_name TEXT NOT NULL,
            admin BOOLEAN NOT NULL
        )";
        self.client.execute(sql_statement, &[]).await?;
        
        let sql_statement = "SELECT MAX(uid) FROM users";
        let row = self.client.query_one(sql_statement, &[]).await.unwrap();
        if row.is_empty() {
            self.next_uid = row.get(0);
        } else {
            self.next_uid = 0;
        }

        Ok(())
    }

    pub async fn add_user(&self, user: &User, password: &str) -> Result<u64, Error> {
        println!("Adding {} {} ({}) to database", user.first_name, user.last_name, user.username);
        let sql_statement = "INSERT INTO users(username, password_hash, first_name, last_name, admin)
            VALUES($1::TEXT, $2::TEXT, $3::TEXT, $4::TEXT, $5::BOOLEAN)
        ";
        self.client.execute(sql_statement, &[&user.username, &password, &user.first_name, &user.last_name, &user.admin]).await
    }

    pub async fn get_user_id(&self, username: &str) -> Option<i32> {
        let sql_statement = "SELECT uid FROM users WHERE username = $1::TEXT";
        let row = match self.client.query_one(sql_statement, &[&username]).await {
            Ok(row) => row,
            Err(_) => return None,
        };

        match row.try_get(0) {
            Ok(uid) => uid,
            Err(_) => None,
        }
    }
    
    pub async fn get_is_admin(&self, uid: i32) -> bool {
        let sql_statement = "SELECT admin FROM users WHERE uid = $1::INT";
        let row = match self.client.query_one(sql_statement, &[&uid]).await {
            Ok(row) => row,
            Err(_) => return false,
        };
    
        match row.try_get(0) {
            Ok(uid) => uid,
            Err(_) => false,
        }
    }

    pub async fn get_user_password_hash(&self, uid: i32) -> Option<String> {
        let sql_statement = "SELECT password_hash FROM users WHERE uid = $1::INT";
        let row = match self.client.query_one(sql_statement, &[&uid]).await {
            Ok(row) => row,
            Err(_) => return None,
        };
        
        match row.try_get(0) {
            Ok(hash) => hash,
            Err(_) => None,
        }
    }

    pub async fn get_all_users(&self) -> Vec<User> {
        let mut users = Vec::<User>::new();
        let sql_statement = "SELECT username, first_name, last_name, admin FROM users";
        match self.client.query(sql_statement, &[]).await {
            Ok(rows) => {
                for row in rows {
                    let user = User {
                        username: row.get(0),
                        first_name: row.get(1),
                        last_name: row.get(2),
                        admin: row.get(3)
                    };
                    users.insert(0, user);
                }
            },
            Err(_) => return Vec::new(),
        };
        users
    }

    pub async fn get_user(&self, uid: i32) -> Option<User> {
        let sql_statement = "SELECT username, first_name, last_name, admin FROM users WHERE uid = $1::INT";
        let row = match self.client.query_one(sql_statement, &[&uid]).await {
            Ok(row) => row,
            Err(_) => return None,
        };

        Some(User {
            username: row.get(0),
            first_name: row.get(1),
            last_name: row.get(2),
            admin: row.get(3)
        })
    }

    pub async fn update_user(&self, uid: i32, user: &User) -> Result<u64, Error> {
        let sql_statement = "UPDATE users
            SET username = $1::TEXT, first_name = $2::TEXT, last_name = $3::TEXT
            WHERE uid = $4::INT
        ";
        self.client.execute(sql_statement, &[&user.username, &user.first_name, &user.last_name, &uid]).await
    }

    pub async fn delete_user(&self, uid: i32) -> Result<u64, Error> {
        let sql_statement = "DELETE FROM users WHERE uid = $1::INT";
        self.client.execute(sql_statement, &[&uid]).await
    }
}
