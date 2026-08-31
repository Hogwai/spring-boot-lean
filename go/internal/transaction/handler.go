package transaction

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	service *Service
}

func NewHandler(s *Service) *Handler {
	return &Handler{service: s}
}

// GET /api/transactions?accountNumber=&limit=
func (h *Handler) FindByAccount(c *gin.Context) {
	accountNumber := c.Query("accountNumber")
	limitStr := c.DefaultQuery("limit", "20")
	if limitStr == "" {
		limitStr = "20"
	}

	if accountNumber == "" {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "accountNumber is required"})
		return
	}
	if strings.TrimSpace(accountNumber) == "" {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "accountNumber is required"})
		return
	}

	limit, err := strconv.Atoi(limitStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "limit must be between 1 and 50"})
		return
	}
	if limit < 1 || limit > 50 {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "limit must be between 1 and 50"})
		return
	}

	transactions, err := h.service.FindByAccount(c.Request.Context(), accountNumber, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Internal error"})
		return
	}
	c.JSON(http.StatusOK, transactions)
}

// GET /api/transactions/:id
func (h *Handler) FindByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid id"})
		return
	}
	t, err := h.service.FindByID(c.Request.Context(), id)
	if err != nil {
		var nf *NotFoundError
		if errors.As(err, &nf) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: nf.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Internal error"})
		return
	}
	c.JSON(http.StatusOK, t)
}

// POST /api/transactions
func (h *Handler) Create(c *gin.Context) {
	var req CreateTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid request body"})
		return
	}
	created, err := h.service.Create(c.Request.Context(), req.AccountNumber, req.Amount, req.Description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Internal error"})
		return
	}
	c.JSON(http.StatusCreated, created)
}

// PUT /api/transactions/:id
func (h *Handler) Update(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid id"})
		return
	}
	var req UpdateTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid request body"})
		return
	}
	updated, err := h.service.Update(c.Request.Context(), id, req.AccountNumber, req.Amount, req.Description)
	if err != nil {
		var nf *NotFoundError
		if errors.As(err, &nf) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: nf.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Internal error"})
		return
	}
	c.JSON(http.StatusOK, updated)
}
