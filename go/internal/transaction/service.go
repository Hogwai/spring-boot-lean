package transaction

import (
	"context"
	"fmt"

	"github.com/shopspring/decimal"
)

type Service struct {
	store Store
}

func NewService(store Store) *Service {
	return &Service{store: store}
}

func (s *Service) FindByAccount(ctx context.Context, accountNumber string, limit int) ([]Transaction, error) {
	return s.store.FindByAccountNumber(ctx, accountNumber, limit)
}

func (s *Service) FindByID(ctx context.Context, id int64) (*Transaction, error) {
	t, err := s.store.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, &NotFoundError{ID: id}
	}
	return t, nil
}

func (s *Service) Create(ctx context.Context, accountNumber string, amount decimal.Decimal, description *string) (Transaction, error) {
	t := Transaction{
		AccountNumber: accountNumber,
		Amount:        amount,
		Description:   description,
	}
	return s.store.Save(ctx, t)
}

func (s *Service) Update(ctx context.Context, id int64, accountNumber string, amount decimal.Decimal, description *string) (Transaction, error) {
	existing, err := s.FindByID(ctx, id)
	if err != nil {
		return Transaction{}, err
	}
	updated := Transaction{
		ID:            existing.ID,
		AccountNumber: accountNumber,
		Amount:        amount,
		Description:   description,
		CreatedAt:     existing.CreatedAt,
	}
	return s.store.Save(ctx, updated)
}

type NotFoundError struct {
	ID int64
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("Transaction not found: %d", e.ID)
}
