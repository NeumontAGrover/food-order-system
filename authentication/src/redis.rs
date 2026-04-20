use redis::{AsyncCommands, RedisError, aio::MultiplexedConnection};

pub struct RedisClient {
    client: MultiplexedConnection,
}

impl RedisClient {
    pub async fn new() -> Result<RedisClient, RedisError> {
        let client = redis::Client::open("redis://redis-auth:6379")?;
        let connection = client.get_multiplexed_async_connection().await?;
        Ok(RedisClient { client: connection })
    }

    pub async fn add_token(&mut self, uid: i32, token: &str) -> Result<(), RedisError> {
        let key = format!("user:{}", uid);
        self.client.set_ex::<_, _, ()>(key, token, 604800).await?;
        Ok(())
    }
    
    pub async fn is_token_expired(&mut self, uid: i32) -> bool {
        let key = format!("user:{}", uid);
        let redis_token: Result<String, RedisError> = self.client.get(key).await;
        match redis_token {
            Ok(_) => false,
            Err(_) => true,
        }
    }
}
