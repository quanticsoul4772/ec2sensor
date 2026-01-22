package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/quanticsoul4772/ec2sensor-go/models"
)

const (
	// Unicode symbols
	IconSuccess  = "✓"
	IconError    = "✗"
	IconWarning  = "⚠"
	IconInfo     = "ℹ"
	IconRunning  = "●"
	IconPending  = "○"
	IconStopped  = "◌"
	IconArrow    = "›"
	IconBullet   = "•"
	IconCheck    = "✓"
	IconCheckbox = "☑"
	IconEmpty    = "☐"

	// Box drawing
	BoxTL = "╭"
	BoxTR = "╮"
	BoxBL = "╰"
	BoxBR = "╯"
	BoxH  = "─"
	BoxV  = "│"
)

// RenderHeader renders a centered header with box border
func RenderHeader(s Styles, title, subtitle string) string {
	var content string
	if subtitle != "" {
		content = fmt.Sprintf("%s  %s", title, subtitle)
	} else {
		content = title
	}
	return s.Header.Render(content)
}

// RenderBreadcrumb renders navigation breadcrumbs
func RenderBreadcrumb(s Styles, parts ...string) string {
	var result strings.Builder
	for i, part := range parts {
		if i > 0 {
			result.WriteString(fmt.Sprintf(" %s ", IconArrow))
		}
		result.WriteString(part)
	}
	return s.Breadcrumb.Render(result.String())
}

// RenderSection renders a section header with underline
func RenderSection(s Styles, title string) string {
	return s.Section.Render(title)
}

// RenderStatusIcon returns a colored status icon
func RenderStatusIcon(s Styles, status models.SensorStatus) string {
	switch status {
	case models.StatusRunning:
		return s.StatusRunning.Render(IconRunning + " RUNNING")
	case models.StatusPending:
		return s.StatusPending.Render(IconPending + " PENDING")
	case models.StatusStopped:
		return s.StatusStopped.Render(IconStopped + " STOPPED")
	case models.StatusError:
		return s.StatusError.Render(IconError + " ERROR")
	default:
		return s.StatusStopped.Render("? UNKNOWN")
	}
}

// RenderHealthValue renders a health metric with color coding
func RenderHealthValue(s Styles, value int) string {
	if value < 0 {
		return s.Help.Render("-")
	}
	valStr := fmt.Sprintf("%d%%", value)
	if value < 60 {
		return s.HealthGood.Render(valStr)
	} else if value < 80 {
		return s.HealthWarning.Render(valStr)
	}
	return s.HealthCritical.Render(valStr)
}

// RenderProgressBar renders a visual progress bar
func RenderProgressBar(s Styles, current, total, width int) string {
	if total == 0 {
		total = 1
	}
	filled := (current * width) / total
	if filled > width {
		filled = width
	}
	empty := width - filled

	var bar strings.Builder
	bar.WriteString("[")
	bar.WriteString(s.HealthGood.Render(strings.Repeat("█", filled)))
	bar.WriteString(s.Help.Render(strings.Repeat("░", empty)))
	bar.WriteString("]")

	return bar.String()
}

// RenderMessage renders a styled message with icon
func RenderMessage(s Styles, msgType string, message string, detail string) string {
	var icon, styledMsg string
	switch msgType {
	case "success":
		icon = s.Success.Render(IconSuccess)
		styledMsg = s.Success.Render(message)
	case "error":
		icon = s.Error.Render(IconError)
		styledMsg = s.Error.Bold(true).Render(message)
	case "warning":
		icon = s.Warning.Render(IconWarning)
		styledMsg = s.Warning.Render(message)
	case "info":
		icon = s.Info.Render(IconInfo)
		styledMsg = message
	default:
		icon = IconBullet
		styledMsg = message
	}

	result := fmt.Sprintf("  %s %s", icon, styledMsg)
	if detail != "" {
		result += fmt.Sprintf("\n      %s", s.Help.Render(detail))
	}
	return result
}

// RenderKeyValue renders a key-value pair
func RenderKeyValue(s Styles, key, value string) string {
	return fmt.Sprintf("  %s %-18s %s", 
		s.Help.Render(IconBullet),
		s.Info.Render(key),
		value)
}

// RenderMenuItem renders a menu option
func RenderMenuItem(s Styles, key, label, description string, active bool) string {
	var keyStyle lipgloss.Style
	if active {
		keyStyle = s.MenuItemActive
	} else {
		keyStyle = s.MenuShortcut
	}

	result := fmt.Sprintf("  %s  %s", keyStyle.Render("["+key+"]"), label)
	if description != "" {
		result += fmt.Sprintf("\n       %s", s.Help.Render(description))
	}
	return result
}

// RenderShortcuts renders keyboard shortcuts footer
func RenderShortcuts(s Styles, shortcuts []Shortcut) string {
	var parts []string
	for _, sc := range shortcuts {
		parts = append(parts, fmt.Sprintf("%s%s%s%s",
			s.Help.Render("["),
			s.MenuShortcut.Render(sc.Key),
			s.Help.Render("]"),
			s.Help.Render(sc.Label)))
	}
	return strings.Join(parts, "  ")
}

// Shortcut represents a keyboard shortcut
type Shortcut struct {
	Key   string
	Label string
}

// MainShortcuts returns shortcuts for main view
func MainShortcuts() []Shortcut {
	return []Shortcut{
		{"r", "efresh"},
		{"n", "ew"},
		{"m", "ulti-select"},
		{"t", "heme"},
		{"q", "uit"},
		{"?", "help"},
	}
}

// OperationsShortcuts returns shortcuts for operations view
func OperationsShortcuts() []Shortcut {
	return []Shortcut{
		{"c", "onnect"},
		{"f", "eatures"},
		{"u", "pgrade"},
		{"d", "elete"},
		{"h", "ealth"},
		{"b", "ack"},
		{"q", "uit"},
	}
}

// RenderStatusBar renders the bottom status bar
func RenderStatusBar(s Styles, running, errors int, sessionDuration, refreshAge time.Duration) string {
	var parts []string

	// Refresh age
	ageStr := formatDuration(refreshAge)
	if refreshAge.Seconds() < 10 {
		parts = append(parts, s.HealthGood.Render(fmt.Sprintf("[Last Updated: %s ago]", ageStr)))
	} else if refreshAge.Seconds() < 60 {
		parts = append(parts, s.HealthWarning.Render(fmt.Sprintf("[Last Updated: %s ago]", ageStr)))
	} else {
		parts = append(parts, s.HealthCritical.Render(fmt.Sprintf("[Last Updated: %s ago]", ageStr)))
	}

	// Running count
	if running > 0 {
		parts = append(parts, s.HealthGood.Render(fmt.Sprintf("[%d Running]", running)))
	} else {
		parts = append(parts, "[0 Running]")
	}

	// Error count
	if errors > 0 {
		parts = append(parts, s.HealthCritical.Render(fmt.Sprintf("[%d Errors]", errors)))
	} else {
		parts = append(parts, "[0 Errors]")
	}

	// Session duration
	parts = append(parts, fmt.Sprintf("[Session: %s]", formatDuration(sessionDuration)))

	return s.StatusBar.Render(strings.Join(parts, " "))
}

// formatDuration formats a duration in human-readable form
func formatDuration(d time.Duration) string {
	secs := int(d.Seconds())
	if secs < 60 {
		return fmt.Sprintf("%ds", secs)
	} else if secs < 3600 {
		mins := secs / 60
		remSecs := secs % 60
		return fmt.Sprintf("%dm %ds", mins, remSecs)
	} else if secs < 86400 {
		hours := secs / 3600
		mins := (secs % 3600) / 60
		return fmt.Sprintf("%dh %dm", hours, mins)
	}
	days := secs / 86400
	hours := (secs % 86400) / 3600
	return fmt.Sprintf("%dd %dh", days, hours)
}

// RenderSensorTable renders the sensor list as a table
func RenderSensorTable(s Styles, sensors []*models.Sensor, cursor int, multiSelect bool) string {
	var b strings.Builder

	// Table border
	border := s.TableBorder.Render(strings.Repeat("─", 68))
	b.WriteString(border)
	b.WriteString("\n")

	// Header
	header := fmt.Sprintf("%-4s %-10s %-12s %6s %6s %6s %5s  %-15s",
		"ID", "SENSOR", "STATUS", "CPU%", "MEM%", "DISK%", "PODS", "IP")
	b.WriteString(s.TableHeader.Render(header))
	b.WriteString("\n")
	b.WriteString(border)
	b.WriteString("\n")

	// Rows
	for i, sensor := range sensors {
		if sensor.Deleted {
			continue
		}

		// Row content
		id := fmt.Sprintf("%d", i+1)
		shortID := sensor.ShortID()
		status := RenderStatusIcon(s, sensor.Status)

		var cpu, mem, disk, pods string
		if sensor.HasMetrics() {
			cpu = RenderHealthValue(s, sensor.Metrics.CPU)
			mem = RenderHealthValue(s, sensor.Metrics.Memory)
			disk = RenderHealthValue(s, sensor.Metrics.Disk)
			pods = fmt.Sprintf("%d", sensor.Metrics.Pods)
		} else {
			cpu = s.Help.Render(" -")
			mem = s.Help.Render(" -")
			disk = s.Help.Render(" -")
			pods = s.Help.Render(" -")
		}

		ip := sensor.IP
		if ip == "" || ip == "null" {
			ip = "no-ip"
		}

		// Selection indicator
		var prefix string
		if multiSelect {
			// Multi-select mode: show checkboxes
			if sensor.Selected {
				prefix = s.Success.Render("[" + IconCheck + "]")
			} else {
				prefix = s.Help.Render("[ ]")
			}
		} else {
			// Normal mode: show arrow for selected row
			if i == cursor {
				prefix = s.Info.Render(IconArrow + " ")
			} else {
				prefix = "  "
			}
		}

		// Build row - handle color codes in status by padding separately
		row := fmt.Sprintf("%s %-4s %-10s %-25s %6s %6s %6s %5s  %-15s",
			prefix, id, shortID, status, cpu, mem, disk, pods, ip)

		// Apply row style (no background highlight to preserve colored indicators)
		b.WriteString(s.TableRow.Render(row))
		b.WriteString("\n")
	}

	// Bottom border
	b.WriteString(border)

	return b.String()
}

// RenderHelp renders the help screen
func RenderHelp(s Styles, context string) string {
	var b strings.Builder

	b.WriteString(RenderHeader(s, "KEYBOARD SHORTCUTS", "Help"))
	b.WriteString("\n\n")

	b.WriteString(RenderSection(s, "Navigation"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  %s     Select item by number\n", s.MenuShortcut.Render("1-9")))
	b.WriteString(fmt.Sprintf("  %s   Navigate up/down\n", s.MenuShortcut.Render("j/k")))
	b.WriteString(fmt.Sprintf("  %s Navigate up/down\n", s.MenuShortcut.Render("↑/↓")))
	b.WriteString(fmt.Sprintf("  %s   Confirm selection\n", s.MenuShortcut.Render("Enter")))
	b.WriteString(fmt.Sprintf("  %s       Show this help\n", s.MenuShortcut.Render("?")))
	b.WriteString("\n")

	switch context {
	case "main":
		b.WriteString(RenderSection(s, "Main Menu Shortcuts"))
		b.WriteString("\n")
		b.WriteString(fmt.Sprintf("  %s       Refresh sensor list\n", s.MenuShortcut.Render("r")))
		b.WriteString(fmt.Sprintf("  %s       Deploy new sensor\n", s.MenuShortcut.Render("n")))
		b.WriteString(fmt.Sprintf("  %s       Multi-select mode\n", s.MenuShortcut.Render("m")))
		b.WriteString(fmt.Sprintf("  %s       Cycle color theme\n", s.MenuShortcut.Render("t")))
		b.WriteString(fmt.Sprintf("  %s       Quit application\n", s.MenuShortcut.Render("q")))
	case "operations":
		b.WriteString(RenderSection(s, "Sensor Operations Shortcuts"))
		b.WriteString("\n")
		b.WriteString(fmt.Sprintf("  %s       Connect via SSH\n", s.MenuShortcut.Render("c")))
		b.WriteString(fmt.Sprintf("  %s       Enable features\n", s.MenuShortcut.Render("f")))
		b.WriteString(fmt.Sprintf("  %s       Upgrade sensor\n", s.MenuShortcut.Render("u")))
		b.WriteString(fmt.Sprintf("  %s       Delete sensor\n", s.MenuShortcut.Render("d")))
		b.WriteString(fmt.Sprintf("  %s       Health dashboard\n", s.MenuShortcut.Render("h")))
		b.WriteString(fmt.Sprintf("  %s       Back to list\n", s.MenuShortcut.Render("b")))
	}

	b.WriteString("\n")
	b.WriteString(RenderSection(s, "Tips"))
	b.WriteString("\n")
	b.WriteString("  • Shortcuts are case-insensitive\n")
	b.WriteString("  • Use Ctrl+C to exit at any time\n")
	b.WriteString("  • Set EC2SENSOR_THEME=light for light terminals\n")
	b.WriteString("\n")
	b.WriteString(s.Help.Render("  Press any key to return..."))

	return b.String()
}
