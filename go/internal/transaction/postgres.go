package transaction

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

func scanTransaction(row pgx.Row) (Transaction, error) {
	var t Transaction
	var amount pgtype.Numeric
	var description *string
	var createdAt time.Time
	var id int64
	var accountNumber string

	err := row.Scan(&id, &accountNumber, &amount, &description, &createdAt)
	if err != nil {
		return Transaction{}, err
	}
	amt, err := numericToDecimal(amount)
	if err != nil {
		return Transaction{}, err
	}
	t.ID = id
	t.AccountNumber = accountNumber
	t.Amount = amt
	t.Description = description
	t.CreatedAt = createdAt.UTC()
	return t, nil
}

func numericToDecimal(n pgtype.Numeric) (decimal.Decimal, error) {
	if !n.Valid {
		return decimal.Zero, nil
	}
	if n.NaN {
		return decimal.Zero, nil
	}
	if n.Int == nil {
		return decimal.Zero, nil
	}
	return decimal.NewFromBigInt(n.Int, n.Exp), nil
}

func (r *PostgresStore) FindByID(ctx context.Context, id int64) (*Transaction, error) {
	row := r.pool.QueryRow(ctx,
		"SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1", id)
	t, err := scanTransaction(row)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &t, nil
}

func (r *PostgresStore) FindByAccountNumber(ctx context.Context, accountNumber string, limit int) ([]Transaction, error) {
	rows, err := r.pool.Query(ctx,
		"SELECT id, account_number, amount, description, created_at FROM transaction WHERE account_number = $1 ORDER BY id LIMIT $2",
		accountNumber, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Transaction
	for rows.Next() {
		var id int64
		var acc string
		var amount pgtype.Numeric
		var desc *string
		var createdAt time.Time
		if err := rows.Scan(&id, &acc, &amount, &desc, &createdAt); err != nil {
			return nil, err
		}
		amt, err := numericToDecimal(amount)
		if err != nil {
			return nil, err
		}
		result = append(result, Transaction{
			ID:            id,
			AccountNumber: acc,
			Amount:        amt,
			Description:   desc,
			CreatedAt:     createdAt.UTC(),
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if result == nil {
		result = []Transaction{}
	}
	return result, nil
}

func (r *PostgresStore) Save(ctx context.Context, t Transaction) (Transaction, error) {
	if t.ID == 0 {
		var id int64
		err := r.pool.QueryRow(ctx,
			"INSERT INTO transaction (account_number, amount, description) VALUES ($1, $2, $3) RETURNING id",
			t.AccountNumber, t.Amount.String(), t.Description).Scan(&id)
		if err != nil {
			return Transaction{}, err
		}
		row := r.pool.QueryRow(ctx,
			"SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1", id)
		saved, err := scanTransaction(row)
		if err != nil {
			return Transaction{
				ID:            id,
				AccountNumber: t.AccountNumber,
				Amount:        t.Amount,
				Description:   t.Description,
				CreatedAt:     time.Now().UTC(),
			}, nil
		}
		return saved, nil
	}
	_, err := r.pool.Exec(ctx,
		"UPDATE transaction SET account_number = $1, amount = $2, description = $3 WHERE id = $4",
		t.AccountNumber, t.Amount.String(), t.Description, t.ID)
	if err != nil {
		return Transaction{}, err
	}
	row := r.pool.QueryRow(ctx,
		"SELECT id, account_number, amount, description, created_at FROM transaction WHERE id = $1", t.ID)
	saved, err := scanTransaction(row)
	if err != nil {
		return t, nil
	}
	return saved, nil
}
