package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/quanticsoul4772/ec2sensor-go/config"
	"github.com/quanticsoul4772/ec2sensor-go/models"
)

// Client handles API communication with the EC2 sensor service
type Client struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
	maxRetries int
}

// NewClient creates a new API client
func NewClient(cfg *config.Config) *Client {
	return &Client{
		baseURL: cfg.APIBaseURL,
		apiKey:  cfg.APIKey,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		maxRetries: 3,
	}
}

// FetchSensor retrieves sensor data from the API
func (c *Client) FetchSensor(sensorName string) (*models.Sensor, error) {
	url := fmt.Sprintf("%s/%s", c.baseURL, sensorName)

	var lastErr error
	for attempt := 0; attempt < c.maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * time.Second) // Exponential backoff
		}

		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			lastErr = err
			continue
		}

		req.Header.Set("x-api-key", c.apiKey)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}

		body, err := io.ReadAll(resp.Body)
		resp.Body.Close() // Close immediately, not deferred in loop
		if err != nil {
			lastErr = err
			continue
		}

		// Check for error response (plain text)
		bodyStr := string(body)
		if strings.Contains(bodyStr, "Error:") && strings.Contains(bodyStr, "does not exist") {
			// Sensor doesn't exist in API - mark as deleted so it gets cleaned up
			return &models.Sensor{
				Name:    sensorName,
				IP:      "",
				Status:  models.StatusDeleted,
				Deleted: true,
				Error:   "Sensor does not exist",
			}, nil
		}

		var sensor models.Sensor
		if err := json.Unmarshal(body, &sensor); err != nil {
			lastErr = fmt.Errorf("failed to parse response: %w", err)
			continue
		}

		// Set defaults if empty
		if sensor.Status == "" {
			sensor.Status = models.StatusUnknown
		}

		// Mark terminated sensors as deleted
		if sensor.Status == "terminated" {
			sensor.Deleted = true
			sensor.Status = models.StatusDeleted
		}

		return &sensor, nil
	}

	return nil, fmt.Errorf("API request failed after %d attempts: %v", c.maxRetries, lastErr)
}

// DeleteSensor deletes a sensor via the API
func (c *Client) DeleteSensor(sensorName string) error {
	url := fmt.Sprintf("%s/delete/%s", c.baseURL, sensorName)

	req, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		return err
	}

	req.Header.Set("x-api-key", c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("delete failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// CreateSensorRequest holds the payload for creating a new sensor
type CreateSensorRequest struct {
	DevelopmentBranch string `json:"development_branch"`
	TeamName          string `json:"team_name"`
	Username          string `json:"username"`
}

// CreateSensorResponse holds the response from creating a sensor
type CreateSensorResponse struct {
	EC2SensorName string `json:"ec2_sensor_name"`
	SensorIP      string `json:"sensor_ip"`
	SensorStatus  string `json:"sensor_status"`
}

// CreateSensor creates a new sensor via the API
func (c *Client) CreateSensor() (string, error) {
	url := fmt.Sprintf("%s/create", c.baseURL)

	// Default values matching the bash script
	payload := CreateSensorRequest{
		DevelopmentBranch: "testing",
		TeamName:          "cicd",
		Username:          "codebuff", // Default username
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", url, strings.NewReader(string(jsonPayload)))
	if err != nil {
		return "", err
	}

	req.Header.Set("accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)

	// Use a longer timeout for creation
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("create failed with status %d: %s", resp.StatusCode, string(body))
	}

	var createResp CreateSensorResponse
	if err := json.Unmarshal(body, &createResp); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	if createResp.EC2SensorName == "" {
		return "", fmt.Errorf("no sensor name in response")
	}

	return createResp.EC2SensorName, nil
}

// TestConnectivity checks if the API is reachable
func (c *Client) TestConnectivity() bool {
	url := fmt.Sprintf("%s/test-connectivity-check", c.baseURL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return false
	}

	req.Header.Set("x-api-key", c.apiKey)

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	// Any response (even 404 for non-existent sensor) means API is reachable
	return resp.StatusCode < 500
}
