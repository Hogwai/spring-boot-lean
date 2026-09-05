use super::Transaction;
use sqlx::PgPool;

#[derive(Clone)]
pub struct PostgresStore {
    pub pool: PgPool,
}

impl PostgresStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl super::Store for PostgresStore {
    async fn find_by_id(&self, id: i64) -> Result<Option<Transaction>, sqlx::Error> {
        let tx = sqlx::query_as::<_, Transaction>(
            "SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(tx)
    }

    async fn find_by_account_number(
        &self,
        account_number: &str,
        limit: i64,
    ) -> Result<Vec<Transaction>, sqlx::Error> {
        let rows = sqlx::query_as::<_, Transaction>(
            "SELECT id, account_number, amount, description, created_at FROM transaction WHERE account_number = $1 ORDER BY id LIMIT $2",
        )
        .bind(account_number)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    async fn save(&self, t: Transaction) -> Result<Transaction, sqlx::Error> {
        if t.id == 0 {
            // Insert
            let row = sqlx::query_scalar::<_, i64>(
                "INSERT INTO transaction (account_number, amount, description) VALUES ($1, $2, $3) RETURNING id",
            )
            .bind(&t.account_number)
            .bind(t.amount)
            .bind(&t.description)
            .fetch_one(&self.pool)
            .await?;

            // Try to fetch full row (including created_at)
            let saved = sqlx::query_as::<_, Transaction>(
                "SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1",
            )
            .bind(row)
            .fetch_optional(&self.pool)
            .await?;

            if let Some(s) = saved {
                Ok(s)
            } else {
                // Fallback if fetch fails
                Ok(Transaction {
                    id: row,
                    account_number: t.account_number,
                    amount: t.amount,
                    description: t.description,
                    created_at: chrono::Utc::now(),
                })
            }
        } else {
            sqlx::query(
                "UPDATE transaction SET account_number = $1, amount = $2, description = $3 WHERE id = $4",
            )
            .bind(&t.account_number)
            .bind(t.amount)
            .bind(&t.description)
            .bind(t.id)
            .execute(&self.pool)
            .await?;

            let saved = sqlx::query_as::<_, Transaction>(
                "SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1",
            )
            .bind(t.id)
            .fetch_optional(&self.pool)
            .await?;

            if let Some(s) = saved {
                Ok(s)
            } else {
                Ok(t)
            }
        }
    }
}
