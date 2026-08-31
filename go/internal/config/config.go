package config

import (
	"log"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port        string
	DatabaseURL string
	MaxConns    int32
	MinConns    int32
}

func Load() Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	// Ensure numeric
	if _, err := strconv.Atoi(port); err != nil {
		log.Printf("invalid PORT %q, using 8080", port)
		port = "8080"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		// Try Spring datasource URL
		if springURL := os.Getenv("SPRING_DATASOURCE_URL"); springURL != "" {
			dbURL = ConvertJdbcURL(springURL)
		} else {
			// Also check spring.datasource.url via env file?
			dbURL = "postgres://springlean:springlean@localhost:5432/springlean?sslmode=disable"
		}
	} else if strings.HasPrefix(dbURL, "jdbc:") {
		dbURL = ConvertJdbcURL(dbURL)
	}

	// Also check if DATABASE_URL was set via jdbc prefix indirectly
	// Handle SPRING_DATASOURCE_URL even if DATABASE_URL set? spec says support both
	if springURL := os.Getenv("SPRING_DATASOURCE_URL"); springURL != "" && dbURL == "postgres://springlean:springlean@localhost:5432/springlean?sslmode=disable" {
		// Only override default, not explicit DATABASE_URL
		_ = springURL
	}

	// Allow overriding via SPRING_DATASOURCE_URL even when DATABASE_URL not set we already handled
	// If both set, DATABASE_URL takes precedence unless it was default
	// Additionally if SPRING_DATASOURCE_URL is set and DATABASE_URL is jdbc, we already converted

	return Config{
		Port:        port,
		DatabaseURL: dbURL,
		MaxConns:    20,
		MinConns:    10,
	}
}

// ConvertJdbcURL converts jdbc:postgresql://host:port/db to postgres://...
func ConvertJdbcURL(jdbcURL string) string {
	// jdbc:postgresql://localhost:5432/springlean
	// -> postgres://localhost:5432/springlean?sslmode=disable
	s := strings.TrimPrefix(jdbcURL, "jdbc:")
	// s is now postgresql://...
	// pgx expects postgres:// or postgresql:// both work, but normalize to postgres://
	// Ensure sslmode
	if strings.Contains(s, "?") {
		if !strings.Contains(s, "sslmode") {
			s += "&sslmode=disable"
		}
	} else {
		s += "?sslmode=disable"
	}
	// Inject credentials if missing and not in URL? Spring config separates username/password
	// Try to add from env if not present
	if !strings.Contains(s, "@") {
		user := os.Getenv("SPRING_DATASOURCE_USERNAME")
		if user == "" {
			user = os.Getenv("DATABASE_USER")
		}
		pass := os.Getenv("SPRING_DATASOURCE_PASSWORD")
		if pass == "" {
			pass = os.Getenv("DATABASE_PASSWORD")
		}
		if user == "" {
			user = "springlean"
		}
		if pass == "" {
			pass = "springlean"
		}
		// Insert user:pass@ after scheme://
		if idx := strings.Index(s, "://"); idx != -1 {
			s = s[:idx+3] + user + ":" + pass + "@" + s[idx+3:]
		}
	}
	return s
}
