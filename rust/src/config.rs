use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub port: String,
    pub database_url: String,
}

impl Config {
    pub fn load() -> Self {
        let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
        let port = if port.parse::<u16>().is_ok() {
            port
        } else {
            eprintln!("invalid PORT {:?}, using 8080", port);
            "8080".to_string()
        };

        let database_url = resolve_database_url();

        Self { port, database_url }
    }
}

fn resolve_database_url() -> String {
    let default_url = "postgres://springlean:springlean@localhost:5432/springlean?sslmode=disable".to_string();

    // Check DATABASE_URL first
    if let Ok(url) = env::var("DATABASE_URL") {
        if !url.is_empty() {
            if url.starts_with("jdbc:") {
                return convert_jdbc_url(&url);
            }
            return url;
        }
    }

    // Try SPRING_DATASOURCE_URL
    if let Ok(spring_url) = env::var("SPRING_DATASOURCE_URL") {
        if !spring_url.is_empty() {
            return convert_jdbc_url(&spring_url);
        }
    }

    default_url
}

pub fn convert_jdbc_url(jdbc_url: &str) -> String {
    // jdbc:postgresql://host:port/db -> postgres://...
    let mut s = if jdbc_url.starts_with("jdbc:") {
        jdbc_url.trim_start_matches("jdbc:").to_string()
    } else {
        jdbc_url.to_string()
    };

    // Ensure sslmode
    if s.contains('?') {
        if !s.contains("sslmode") {
            s.push_str("&sslmode=disable");
        }
    } else {
        s.push_str("?sslmode=disable");
    }

    // Inject credentials if missing @
    if !s.contains('@') {
        let user = env::var("SPRING_DATASOURCE_USERNAME")
            .or_else(|_| env::var("DATABASE_USER"))
            .unwrap_or_else(|_| "springlean".to_string());
        let pass = env::var("SPRING_DATASOURCE_PASSWORD")
            .or_else(|_| env::var("DATABASE_PASSWORD"))
            .unwrap_or_else(|_| "springlean".to_string());

        if let Some(idx) = s.find("://") {
            let insert_at = idx + 3;
            s.insert_str(insert_at, &format!("{}:{}@", user, pass));
        }
    }

    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convert_simple() {
        let jdbc = "jdbc:postgresql://localhost:5432/springlean";
        let out = convert_jdbc_url(jdbc);
        assert!(out.contains("postgres"), "{}", out);
        assert!(out.contains("sslmode=disable"));
    }
}
