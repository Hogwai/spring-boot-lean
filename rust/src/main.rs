mod config;
mod transaction;

use axum::{routing::get, Router, Json, http::StatusCode};
use sqlx::postgres::PgPoolOptions;
use std::{sync::Arc, time::{Instant, Duration}};
use tokio::signal;
use transaction::{handler, repository::PostgresStore, service::Service};

#[tokio::main]
async fn main() {
    let start = Instant::now();
    let cfg = config::Config::load();

    eprintln!("starting server on :{}", cfg.port);
    eprintln!("database url: {}", mask_password(&cfg.database_url));

    let pool = PgPoolOptions::new()
        .max_connections(20)
        .acquire_timeout(Duration::from_secs(2))
        .connect_lazy(&cfg.database_url)
        .expect("invalid DATABASE_URL");

    let store = PostgresStore::new(pool);
    let service = Arc::new(Service::new(store));

    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/actuator/health", get(health_handler))
        .route("/api/transactions", get(handler::find_by_account).post(handler::create))
        .route("/api/transactions/{id}", get(handler::find_by_id).put(handler::update))
        .with_state(service);

    let elapsed = start.elapsed().as_millis();
    println!("started in {}ms", elapsed);
    eprintln!("started in {}ms", elapsed);
    eprintln!("listening on :{}", cfg.port);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", cfg.port))
        .await
        .expect("failed to bind");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("server error");
}

async fn health_handler() -> (StatusCode, Json<serde_json::Value>) {
    (StatusCode::OK, Json(serde_json::json!({"status":"UP"})))
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c().await.expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    eprintln!("shutting down server...");
}

fn mask_password(url: &str) -> String {
    if let Some(scheme_idx) = url.find("://") {
        let start = scheme_idx + 3;
        if let Some(at_pos) = url[start..].find('@') {
            let at = start + at_pos;
            if let Some(colon_pos) = url[start..at].find(':') {
                let colon = start + colon_pos;
                return format!("{}***{}", &url[..colon+1], &url[at..]);
            }
        }
    }
    url.to_string()
}
