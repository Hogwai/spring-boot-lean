use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use std::sync::Arc;

use super::service::{FindError, Service};
use super::{CreateTransactionRequest, ErrorResponse, FindByAccountParams, UpdateTransactionRequest};
use super::repository::PostgresStore;

pub type AppService = Arc<Service<PostgresStore>>;

// GET /api/transactions?accountNumber=&limit=
pub async fn find_by_account(
    State(service): State<AppService>,
    Query(params): Query<FindByAccountParams>,
) -> Result<Json<Vec<super::Transaction>>, (StatusCode, Json<ErrorResponse>)> {
    // Validation: accountNumber required and not blank
    let account_number = match params.account_number {
        Some(ref s) if !s.trim().is_empty() => s.trim().to_string(),
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "accountNumber is required".to_string(),
                }),
            ))
        }
    };

    // limit handling: default 20, empty string -> 20
    let limit_str = params.limit.unwrap_or_else(|| "20".to_string());
    let limit_str = if limit_str.is_empty() { "20".to_string() } else { limit_str };

    let limit: i64 = match limit_str.parse() {
        Ok(v) => v,
        Err(_) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "limit must be between 1 and 50".to_string(),
                }),
            ))
        }
    };

    if limit < 1 || limit > 50 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "limit must be between 1 and 50".to_string(),
            }),
        ));
    }

    let result = service
        .find_by_account(&account_number, limit)
        .await
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Internal error".to_string(),
                }),
            )
        })?;

    Ok(Json(result))
}

// GET /api/transactions/:id
pub async fn find_by_id(
    State(service): State<AppService>,
    Path(id_str): Path<String>,
) -> Result<Json<super::Transaction>, (StatusCode, Json<ErrorResponse>)> {
    let id: i64 = id_str.parse().map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Invalid id".to_string(),
            }),
        )
    })?;

    match service.find_by_id(id).await {
        Ok(tx) => Ok(Json(tx)),
        Err(FindError::NotFound(e)) => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: e.to_string(),
            }),
        )),
        Err(FindError::Db(_)) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: "Internal error".to_string(),
            }),
        )),
    }
}

// POST /api/transactions
pub async fn create(
    State(service): State<AppService>,
    body: Result<Json<CreateTransactionRequest>, axum::extract::rejection::JsonRejection>,
) -> Result<(StatusCode, Json<super::Transaction>), (StatusCode, Json<ErrorResponse>)> {
    let Json(req) = body.map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Invalid request body".to_string(),
            }),
        )
    })?;

    let created = service
        .create(req.account_number, req.amount, req.description)
        .await
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Internal error".to_string(),
                }),
            )
        })?;

    Ok((StatusCode::CREATED, Json(created)))
}

// PUT /api/transactions/:id
pub async fn update(
    State(service): State<AppService>,
    Path(id_str): Path<String>,
    body: Result<Json<UpdateTransactionRequest>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<super::Transaction>, (StatusCode, Json<ErrorResponse>)> {
    let id: i64 = id_str.parse().map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Invalid id".to_string(),
            }),
        )
    })?;

    let Json(req) = body.map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Invalid request body".to_string(),
            }),
        )
    })?;

    match service
        .update(id, req.account_number, req.amount, req.description)
        .await
    {
        Ok(tx) => Ok(Json(tx)),
        Err(FindError::NotFound(e)) => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: e.to_string(),
            }),
        )),
        Err(FindError::Db(_)) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: "Internal error".to_string(),
            }),
        )),
    }
}
