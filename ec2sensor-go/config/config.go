package config

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/joho/godotenv"
)

// Config holds all application configuration
type Config struct {
	// API Configuration
	APIBaseURL string
	APIKey     string

	// SSH Configuration
	SSHUsername string
	SSHPassword string
	SSHUseKeys  bool

	// UI Configuration
	Theme string

	// File paths
	SensorsFile     string
	OfflineCacheDir string
}

// Load reads configuration from environment and .env file
func Load() (*Config, error) {
	// Try to load .env file from current directory and parent
	godotenv.Load(".env")
	godotenv.Load("../.env")

	cfg := &Config{
		APIBaseURL:      os.Getenv("EC2_SENSOR_BASE_URL"),
		APIKey:          os.Getenv("EC2_SENSOR_API_KEY"),
		SSHUsername:     getEnvDefault("SSH_USERNAME", "broala"),
		SSHPassword:     os.Getenv("SSH_PASSWORD"),
		Theme:           getEnvDefault("EC2SENSOR_THEME", "dark"),
		SensorsFile:     getEnvDefault("SENSORS_FILE", "../.sensors"),
		OfflineCacheDir: filepath.Join(os.Getenv("HOME"), ".ec2sensor", "cache"),
	}

	// Check for SSH keys
	if cfg.SSHPassword == "" {
		home := os.Getenv("HOME")
		if _, err := os.Stat(filepath.Join(home, ".ssh", "id_rsa")); err == nil {
			cfg.SSHUseKeys = true
		} else if _, err := os.Stat(filepath.Join(home, ".ssh", "id_ed25519")); err == nil {
			cfg.SSHUseKeys = true
		}
	}

	return cfg, nil
}

// Validate checks that required configuration is present
func (c *Config) Validate() error {
	if c.APIBaseURL == "" {
		return fmt.Errorf("EC2_SENSOR_BASE_URL is required")
	}
	if c.APIKey == "" {
		return fmt.Errorf("EC2_SENSOR_API_KEY is required")
	}
	return nil
}

func getEnvDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
