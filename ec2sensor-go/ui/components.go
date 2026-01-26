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

// RenderAlertBox renders a prominent alert box for important notifications
// This is more visible than RenderMessage and should be used for critical errors
func RenderAlertBox(s Styles, alertType string, title string, message string, details []string) string {
	var b strings.Builder
	
	// Determine styling based on alert type
	var borderStyle, titleStyle, messageStyle lipgloss.Style
	var icon string
	
	switch alertType {
	case "error":
		borderStyle = s.Error
		titleStyle = s.Error.Bold(true)
		messageStyle = s.Error
		icon = IconError
	case "warning":
		borderStyle = s.Warning
		titleStyle = s.Warning.Bold(true)
		messageStyle = s.Warning
		icon = IconWarning
	case "success":
		borderStyle = s.Success
		titleStyle = s.Success.Bold(true)
		messageStyle = s.Success
		icon = IconSuccess
	case "info":
		borderStyle = s.Info
		titleStyle = s.Info.Bold(true)
		messageStyle = s.Info
		icon = IconInfo
	default:
		borderStyle = s.Help
		titleStyle = s.Help.Bold(true)
		messageStyle = s.Help
		icon = IconBullet
	}
	
	// Calculate box width based on content
	maxWidth := len(title) + 4
	if len(message) > maxWidth {
		maxWidth = len(message)
	}
	for _, detail := range details {
		if len(detail)+2 > maxWidth {
			maxWidth = len(detail) + 2
		}
	}
	if maxWidth < 40 {
		maxWidth = 40
	}
	if maxWidth > 70 {
		maxWidth = 70
	}
	
	// Build the box
	horizontalBorder := strings.Repeat(BoxH, maxWidth+2)
	
	// Top border
	b.WriteString("  ")
	b.WriteString(borderStyle.Render(BoxTL + horizontalBorder + BoxTR))
	b.WriteString("\n")
	
	// Title line with icon
	titleLine := fmt.Sprintf("%s %s", icon, title)
	padding := maxWidth - len(titleLine) + 2
	if padding < 0 {
		padding = 0
	}
	b.WriteString("  ")
	b.WriteString(borderStyle.Render(BoxV))
	b.WriteString(" ")
	b.WriteString(titleStyle.Render(titleLine))
	b.WriteString(strings.Repeat(" ", padding))
	b.WriteString(borderStyle.Render(BoxV))
	b.WriteString("\n")
	
	// Separator
	b.WriteString("  ")
	b.WriteString(borderStyle.Render(BoxV + strings.Repeat(BoxH, maxWidth+2) + BoxV))
	b.WriteString("\n")
	
	// Message line
	if message != "" {
		msgPadding := maxWidth - len(message) + 2
		if msgPadding < 0 {
			msgPadding = 0
		}
		b.WriteString("  ")
		b.WriteString(borderStyle.Render(BoxV))
		b.WriteString(" ")
		b.WriteString(messageStyle.Render(message))
		b.WriteString(strings.Repeat(" ", msgPadding))
		b.WriteString(borderStyle.Render(BoxV))
		b.WriteString("\n")
	}
	
	// Detail lines
	for _, detail := range details {
		detailPadding := maxWidth - len(detail)
		if detailPadding < 0 {
			detailPadding = 0
		}
		b.WriteString("  ")
		b.WriteString(borderStyle.Render(BoxV))
		b.WriteString("   ")
		b.WriteString(s.Help.Render(detail))
		b.WriteString(strings.Repeat(" ", detailPadding))
		b.WriteString(borderStyle.Render(BoxV))
		b.WriteString("\n")
	}
	
	// Bottom border
	b.WriteString("  ")
	b.WriteString(borderStyle.Render(BoxBL + horizontalBorder + BoxBR))
	
	return b.String()
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

	// Column widths (fixed)
	const (
		colPrefix = 3  // "› " or "[ ]"
		colID     = 3  // "1", "2", etc.
		colSensor = 10 // Short sensor ID
		colStatus = 11 // "● RUNNING" etc.
		colCPU    = 5  // "85%" etc.
		colMem    = 5
		colDisk   = 5
		colPods   = 4
		colIP     = 15
	)

	// Table border
	tableWidth := colPrefix + colID + colSensor + colStatus + colCPU + colMem + colDisk + colPods + colIP + 10 // +10 for spacing
	border := s.TableBorder.Render(strings.Repeat("─", tableWidth))
	b.WriteString(border)
	b.WriteString("\n")

	// Header - account for prefix column
	header := fmt.Sprintf("   %-*s %-*s %-*s %*s %*s %*s %*s  %-*s",
		colID, "ID",
		colSensor, "SENSOR",
		colStatus, "STATUS",
		colCPU, "CPU%",
		colMem, "MEM%",
		colDisk, "DISK%",
		colPods, "PODS",
		colIP, "IP")
	b.WriteString(s.TableHeader.Render(header))
	b.WriteString("\n")
	b.WriteString(border)
	b.WriteString("\n")

	// Rows
	for i, sensor := range sensors {
		if sensor.Deleted {
			continue
		}

		// Row content - pad values BEFORE applying colors
		id := fmt.Sprintf("%-*d", colID, i+1)
		shortID := fmt.Sprintf("%-*s", colSensor, sensor.ShortID())
		
		// Status - pad the text, then colorize
		statusText, statusStyle := getStatusTextAndStyle(s, sensor.Status)
		statusText = fmt.Sprintf("%-*s", colStatus, statusText)
		status := statusStyle.Render(statusText)

		// Metrics - pad values before colorizing
		var cpu, mem, disk, pods string
		if sensor.HasMetrics() {
			cpu = renderPaddedHealthValue(s, sensor.Metrics.CPU, colCPU)
			mem = renderPaddedHealthValue(s, sensor.Metrics.Memory, colMem)
			disk = renderPaddedHealthValue(s, sensor.Metrics.Disk, colDisk)
			pods = fmt.Sprintf("%*d", colPods, sensor.Metrics.Pods)
		} else {
			cpu = s.Help.Render(fmt.Sprintf("%*s", colCPU, "-"))
			mem = s.Help.Render(fmt.Sprintf("%*s", colMem, "-"))
			disk = s.Help.Render(fmt.Sprintf("%*s", colDisk, "-"))
			pods = s.Help.Render(fmt.Sprintf("%*s", colPods, "-"))
		}

		ip := sensor.IP
		if ip == "" || ip == "null" {
			ip = "no-ip"
		}
		ip = fmt.Sprintf("%-*s", colIP, ip)

		// Selection indicator (fixed width)
		var prefix string
		if multiSelect {
			if sensor.Selected {
				prefix = s.Success.Render("[" + IconCheck + "]")
			} else {
				prefix = s.Help.Render("[ ]")
			}
		} else {
			if i == cursor {
				prefix = s.Info.Render(IconArrow + " ")
			} else {
				prefix = "  "
			}
		}

		// Build row with consistent spacing
		row := fmt.Sprintf("%s %s %s %s %s %s %s %s  %s",
			prefix, id, shortID, status, cpu, mem, disk, pods, ip)

		b.WriteString(s.TableRow.Render(row))
		b.WriteString("\n")
	}

	// Bottom border
	b.WriteString(border)

	return b.String()
}

// getStatusTextAndStyle returns the plain text and style for a status
func getStatusTextAndStyle(s Styles, status models.SensorStatus) (string, lipgloss.Style) {
	switch status {
	case models.StatusRunning:
		return IconRunning + " RUNNING", s.StatusRunning
	case models.StatusPending:
		return IconPending + " PENDING", s.StatusPending
	case models.StatusStopped:
		return IconStopped + " STOPPED", s.StatusStopped
	case models.StatusError:
		return IconError + " ERROR", s.StatusError
	default:
		return "? UNKNOWN", s.StatusStopped
	}
}

// renderPaddedHealthValue renders a health value with proper padding before colorizing
func renderPaddedHealthValue(s Styles, value int, width int) string {
	if value < 0 {
		return s.Help.Render(fmt.Sprintf("%*s", width, "-"))
	}
	valStr := fmt.Sprintf("%*d%%", width-1, value) // -1 for the % sign
	if value < 60 {
		return s.HealthGood.Render(valStr)
	} else if value < 80 {
		return s.HealthWarning.Render(valStr)
	}
	return s.HealthCritical.Render(valStr)
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
