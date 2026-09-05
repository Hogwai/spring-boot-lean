use super::Transaction;
use rust_decimal::Decimal;

#[derive(Debug, Clone)]
pub struct NotFoundError {
    pub id: i64,
}

impl std::fmt::Display for NotFoundError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Transaction not found: {}", self.id)
    }
}

impl std::error::Error for NotFoundError {}

pub struct Service<S> {
    pub store: S,
}

impl<S> Service<S>
where
    S: super::Store,
{
    pub fn new(store: S) -> Self {
        Self { store }
    }

    pub async fn find_by_account(
        &self,
        account_number: &str,
        limit: i64,
    ) -> Result<Vec<Transaction>, sqlx::Error> {
        self.store.find_by_account_number(account_number, limit).await
    }

    pub async fn find_by_id(&self, id: i64) -> Result<Transaction, FindError> {
        let t = self
            .store
            .find_by_id(id)
            .await
            .map_err(FindError::Db)?;
        match t {
            Some(tx) => Ok(tx),
            None => Err(FindError::NotFound(NotFoundError { id })),
        }
    }

    pub async fn create(
        &self,
        account_number: String,
        amount: Decimal,
        description: Option<String>,
    ) -> Result<Transaction, sqlx::Error> {
        let t = Transaction {
            id: 0,
            account_number,
            amount,
            description,
            created_at: chrono::Utc::now(),
        };
        self.store.save(t).await
    }

    pub async fn update(
        &self,
        id: i64,
        account_number: String,
        amount: Decimal,
        description: Option<String>,
    ) -> Result<Transaction, FindError> {
        let existing = self.find_by_id(id).await?;
        let updated = Transaction {
            id: existing.id,
            account_number,
            amount,
            description,
            created_at: existing.created_at,
        };
        self.store.save(updated).await.map_err(FindError::Db)
    }
}

#[derive(Debug)]
pub enum FindError {
    NotFound(NotFoundError),
    Db(sqlx::Error),
}

impl std::fmt::Display for FindError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FindError::NotFound(e) => write!(f, "{}", e),
            FindError::Db(e) => write!(f, "db error: {}", e),
        }
    }
}

impl std::error::Error for FindError {}
