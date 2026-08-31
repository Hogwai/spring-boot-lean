package transaction

import (
	"context"
	"time"

	"github.com/shopspring/decimal"
)

type Transaction struct {
	ID            int64           `json:"id"`
	AccountNumber string          `json:"accountNumber"`
	Amount        decimal.Decimal `json:"amount"`
	Description   *string         `json:"description"`
	CreatedAt     time.Time       `json:"createdAt"`
}

type CreateTransactionRequest struct {
	AccountNumber string          `json:"accountNumber"`
	Amount        decimal.Decimal `json:"amount"`
	Description   *string         `json:"description"`
}

type UpdateTransactionRequest struct {
	AccountNumber string          `json:"accountNumber"`
	Amount        decimal.Decimal `json:"amount"`
	Description   *string         `json:"description"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

// Store is the consumer-side interface for transaction persistence.
type Store interface {
	FindByID(ctx context.Context, id int64) (*Transaction, error)
	FindByAccountNumber(ctx context.Context, accountNumber string, limit int) ([]Transaction, error)
	Save(ctx context.Context, t Transaction) (Transaction, error)
}
