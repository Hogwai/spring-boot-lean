package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"spring-boot-lean-go/internal/config"
	"spring-boot-lean-go/internal/handler"
	"spring-boot-lean-go/internal/transaction"
)

func main() {
	started := time.Now()
	cfg := config.Load()
	log.Printf("starting server on :%s", cfg.Port)
	log.Printf("database url: %s", maskPassword(cfg.DatabaseURL))

	poolCfg, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("invalid DATABASE_URL: %v", err)
	}
	poolCfg.MaxConns = cfg.MaxConns
	poolCfg.MinConns = cfg.MinConns
	poolCfg.MaxConnLifetime = time.Hour
	poolCfg.MaxConnIdleTime = 30 * time.Minute
	poolCfg.HealthCheckPeriod = 30 * time.Second
	if poolCfg.ConnConfig != nil {
		poolCfg.ConnConfig.ConnectTimeout = 2 * time.Second
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), poolCfg)
	if err != nil {
		log.Fatalf("create pool: %v", err)
	}
	defer pool.Close()

	// Verify connectivity but don't fail startup if DB down
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	if err := pool.Ping(ctx); err != nil {
		log.Printf("warning: db ping failed: %v", err)
	}
	cancel()

	store := transaction.NewPostgresStore(pool)
	svc := transaction.NewService(store)
	txHandler := transaction.NewHandler(svc)

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// Health both endpoints
	r.GET("/health", handler.HealthHandler)
	r.GET("/actuator/health", handler.HealthHandler)

	// Transactions
	r.GET("/api/transactions", txHandler.FindByAccount)
	r.GET("/api/transactions/:id", txHandler.FindByID)
	r.POST("/api/transactions", txHandler.Create)
	r.PUT("/api/transactions/:id", txHandler.Update)

	log.Printf("started in %dms", time.Since(started).Milliseconds())

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		log.Printf("listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Printf("shutting down server...")

	ctxShut, cancelShut := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelShut()
	if err := srv.Shutdown(ctxShut); err != nil {
		log.Printf("server shutdown error: %v", err)
	}
	log.Printf("server exited")
}

func maskPassword(url string) string {
	// Simple mask
	// postgres://user:pass@host/db?sslmode=disable
	// find :// then : then @
	start := -1
	end := -1
	if idx := indexOf(url, "://"); idx != -1 {
		start = idx + 3
		// find @ after start
		at := indexOfFrom(url, "@", start)
		if at != -1 {
			colon := indexOfFrom(url, ":", start)
			if colon != -1 && colon < at {
				end = at
				return url[:colon+1] + "***" + url[end:]
			}
		}
	}
	return url
}

func indexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}

func indexOfFrom(s, substr string, from int) int {
	for i := from; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
