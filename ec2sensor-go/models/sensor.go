package models

import (
	"fmt"
	"time"
)

// SensorStatus represents the current state of a sensor
type SensorStatus string

const (
	StatusRunning  SensorStatus = "running"
	StatusPending  SensorStatus = "pending"
	StatusStopped  SensorStatus = "stopped"
	StatusError    SensorStatus = "error"
	StatusUnknown  SensorStatus = "unknown"
	StatusDeleted  SensorStatus = "deleted"
)

// Sensor represents an EC2 sensor instance
type Sensor struct {
	Name          string       `json:"ec2_sensor_name"`
	IP            string       `json:"sensor_ip"`
	Username      string       `json:"sensor_username"`
	Status        SensorStatus `json:"sensor_status"`
	Type          string       `json:"sensor_type"`
	DevBranch     string       `json:"dev_branch"`
	StackName     string       `json:"stack_name"`
	BrolinVersion string       `json:"brolin_version"`
	CreatedAt     string       `json:"created_at"`

	// Metrics (populated via SSH)
	Metrics        *SensorMetrics
	MetricsUpdated time.Time

	// UI state
	Loading  bool
	Selected bool
	Deleted  bool   `json:"_deleted"`
	Error    string `json:"_error"`
}

// SensorMetrics holds resource usage metrics
type SensorMetrics struct {
	CPU    int    // CPU usage percentage
	Memory int    // Memory usage percentage
	Disk   int    // Disk usage percentage
	Pods   int    // Number of running pods/services
	Uptime string // Human-readable uptime
}

// ShortID returns the last 8 characters of the sensor name
func (s *Sensor) ShortID() string {
	if len(s.Name) > 8 {
		return s.Name[len(s.Name)-8:]
	}
	return s.Name
}

// IsReady returns true if the sensor is in a ready state for operations
func (s *Sensor) IsReady() bool {
	return s.Status == StatusRunning && s.IP != "" && s.IP != "no-ip" && s.IP != "null"
}

// HasMetrics returns true if metrics have been collected
func (s *Sensor) HasMetrics() bool {
	return s.Metrics != nil
}

// GetCPU returns CPU as string or "-" if not available
func (s *Sensor) GetCPU() string {
	if s.Metrics == nil {
		return "-"
	}
	return formatPercent(s.Metrics.CPU)
}

// GetMemory returns memory as string or "-" if not available
func (s *Sensor) GetMemory() string {
	if s.Metrics == nil {
		return "-"
	}
	return formatPercent(s.Metrics.Memory)
}

// GetDisk returns disk as string or "-" if not available
func (s *Sensor) GetDisk() string {
	if s.Metrics == nil {
		return "-"
	}
	return formatPercent(s.Metrics.Disk)
}

// GetPods returns pods count as string or "-" if not available
func (s *Sensor) GetPods() string {
	if s.Metrics == nil {
		return "-"
	}
	return formatInt(s.Metrics.Pods)
}

func formatPercent(v int) string {
	if v < 0 {
		return "-"
	}
	return fmt.Sprintf("%d%%", v)
}

func formatInt(v int) string {
	if v < 0 {
		return "-"
	}
	return fmt.Sprintf("%d", v)
}
