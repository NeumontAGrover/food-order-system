extern crate redis;

fn healthcheck() -> redis::Redisresult<()> {
    let client = redis::Client::open("redis://redis-auth:6379")?;
    let mut connection = client.get_connection()?;

    Ok(());
}
