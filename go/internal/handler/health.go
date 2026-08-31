package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type HealthResponse struct {
	Status string `json:"status"`
}

func HealthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, HealthResponse{Status: "UP"})
}
