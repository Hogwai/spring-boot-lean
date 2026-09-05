pub mod handler;
pub mod repository;
pub mod service;

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

mod decimal_flex {
    use rust_decimal::Decimal;
    use serde::{de, Deserialize, Deserializer, Serializer};
    use std::str::FromStr;

    pub fn serialize<S>(value: &Decimal, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&value.to_string())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Decimal, D::Error>
    where
        D: Deserializer<'de>,
    {
        let v = serde_json::Value::deserialize(deserializer)?;
        match v {
            serde_json::Value::String(s) => Decimal::from_str(&s).map_err(de::Error::custom),
            serde_json::Value::Number(n) => Decimal::from_str(&n.to_string()).map_err(de::Error::custom),
            _ => Err(de::Error::custom("amount must be a number or string")),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Transaction {
    pub id: i64,
    #[serde(rename = "accountNumber")]
    #[sqlx(rename = "account_number")]
    pub account_number: String,
    #[serde(with = "decimal_flex")]
    pub amount: Decimal,
    pub description: Option<String>,
    #[serde(rename = "createdAt")]
    #[sqlx(rename = "created_at")]
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateTransactionRequest {
    #[serde(rename = "accountNumber")]
    pub account_number: String,
    #[serde(with = "decimal_flex")]
    pub amount: Decimal,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateTransactionRequest {
    #[serde(rename = "accountNumber")]
    pub account_number: String,
    #[serde(with = "decimal_flex")]
    pub amount: Decimal,
    pub description: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

// Query params for GET /api/transactions
#[derive(Debug, Deserialize)]
pub struct FindByAccountParams {
    #[serde(rename = "accountNumber")]
    pub account_number: Option<String>,
    pub limit: Option<String>,
}

pub trait Store: Send + Sync {
    fn find_by_id(
        &self,
        id: i64,
    ) -> impl std::future::Future<Output = Result<Option<Transaction>, sqlx::Error>> + Send;

    fn find_by_account_number(
        &self,
        account_number: &str,
        limit: i64,
    ) -> impl std::future::Future<Output = Result<Vec<Transaction>, sqlx::Error>> + Send;

    fn save(
        &self,
        tx: Transaction,
    ) -> impl std::future::Future<Output = Result<Transaction, sqlx::Error>> + Send;
}
