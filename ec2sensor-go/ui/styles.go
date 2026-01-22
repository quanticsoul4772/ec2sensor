package ui

import (
	"github.com/charmbracelet/lipgloss"
)

// Theme represents a color theme for the UI
type Theme struct {
	Name string

	// Primary colors
	Primary   lipgloss.Color
	Secondary lipgloss.Color
	Accent    lipgloss.Color

	// Status colors
	Success lipgloss.Color
	Warning lipgloss.Color
	Error   lipgloss.Color
	Info    lipgloss.Color

	// Text colors
	Text     lipgloss.Color
	Subtle   lipgloss.Color
	Muted    lipgloss.Color

	// Background
	Background lipgloss.Color
}

var (
	// DarkTheme is the default dark color scheme
	DarkTheme = Theme{
		Name:       "dark",
		Primary:    lipgloss.Color("39"),  // Blue
		Secondary:  lipgloss.Color("63"),  // Purple
		Accent:     lipgloss.Color("39"),  // Blue
		Success:    lipgloss.Color("42"),  // Green
		Warning:    lipgloss.Color("214"), // Yellow/Orange
		Error:      lipgloss.Color("196"), // Red
		Info:       lipgloss.Color("39"),  // Blue
		Text:       lipgloss.Color("252"), // Light gray
		Subtle:     lipgloss.Color("240"), // Gray
		Muted:      lipgloss.Color("236"), // Dark gray
		Background: lipgloss.Color("234"), // Very dark gray
	}

	// LightTheme is for light terminal backgrounds
	LightTheme = Theme{
		Name:       "light",
		Primary:    lipgloss.Color("25"),  // Dark blue
		Secondary:  lipgloss.Color("55"),  // Dark purple
		Accent:     lipgloss.Color("25"),  // Dark blue
		Success:    lipgloss.Color("28"),  // Dark green
		Warning:    lipgloss.Color("130"), // Dark orange
		Error:      lipgloss.Color("124"), // Dark red
		Info:       lipgloss.Color("25"),  // Dark blue
		Text:       lipgloss.Color("232"), // Nearly black
		Subtle:     lipgloss.Color("240"), // Gray
		Muted:      lipgloss.Color("250"), // Light gray
		Background: lipgloss.Color("231"), // White
	}

	// MinimalTheme uses no colors
	MinimalTheme = Theme{
		Name:       "minimal",
		Primary:    lipgloss.Color("7"),
		Secondary:  lipgloss.Color("7"),
		Accent:     lipgloss.Color("7"),
		Success:    lipgloss.Color("7"),
		Warning:    lipgloss.Color("7"),
		Error:      lipgloss.Color("7"),
		Info:       lipgloss.Color("7"),
		Text:       lipgloss.Color("7"),
		Subtle:     lipgloss.Color("8"),
		Muted:      lipgloss.Color("8"),
		Background: lipgloss.Color("0"),
	}
)

// Styles contains all the styled components for the UI
type Styles struct {
	Theme Theme

	// Layout styles
	App       lipgloss.Style
	Header    lipgloss.Style
	Title     lipgloss.Style
	Subtitle  lipgloss.Style
	Section   lipgloss.Style

	// Table styles
	TableHeader    lipgloss.Style
	TableRow       lipgloss.Style
	TableRowAlt    lipgloss.Style
	TableRowSelected lipgloss.Style
	TableCell      lipgloss.Style
	TableBorder    lipgloss.Style

	// Status styles
	StatusRunning lipgloss.Style
	StatusPending lipgloss.Style
	StatusError   lipgloss.Style
	StatusStopped lipgloss.Style

	// Message styles
	Success lipgloss.Style
	Warning lipgloss.Style
	Error   lipgloss.Style
	Info    lipgloss.Style

	// Health indicator styles
	HealthGood    lipgloss.Style
	HealthWarning lipgloss.Style
	HealthCritical lipgloss.Style

	// Menu styles
	MenuItem       lipgloss.Style
	MenuItemActive lipgloss.Style
	MenuShortcut   lipgloss.Style

	// Misc styles
	Help       lipgloss.Style
	StatusBar  lipgloss.Style
	Breadcrumb lipgloss.Style
}

// NewStyles creates a new Styles instance with the given theme
func NewStyles(theme Theme) Styles {
	return Styles{
		Theme: theme,

		// Layout styles
		App: lipgloss.NewStyle().
			Padding(1, 2),

		Header: lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.Accent).
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(theme.Accent).
			Padding(0, 2).
			Width(60).
			Align(lipgloss.Center),

		Title: lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.Accent),

		Subtitle: lipgloss.NewStyle().
			Foreground(theme.Subtle),

		Section: lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.Accent).
			MarginTop(1).
			BorderStyle(lipgloss.NormalBorder()).
			BorderBottom(true).
			BorderForeground(theme.Accent),

		// Table styles
		TableHeader: lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.Text).
			Padding(0, 1),

		TableRow: lipgloss.NewStyle().
			Padding(0, 1),

		TableRowAlt: lipgloss.NewStyle().
			Padding(0, 1),

		TableRowSelected: lipgloss.NewStyle().
			Bold(true).
			Padding(0, 1),

		TableCell: lipgloss.NewStyle().
			Padding(0, 1),

		TableBorder: lipgloss.NewStyle().
			Foreground(theme.Subtle),

		// Status styles
		StatusRunning: lipgloss.NewStyle().
			Foreground(theme.Success),

		StatusPending: lipgloss.NewStyle().
			Foreground(theme.Warning),

		StatusError: lipgloss.NewStyle().
			Foreground(theme.Error),

		StatusStopped: lipgloss.NewStyle().
			Foreground(theme.Warning),

		// Message styles
		Success: lipgloss.NewStyle().
			Foreground(theme.Success),

		Warning: lipgloss.NewStyle().
			Foreground(theme.Warning),

		Error: lipgloss.NewStyle().
			Foreground(theme.Error),

		Info: lipgloss.NewStyle().
			Foreground(theme.Info),

		// Health indicator styles
		HealthGood: lipgloss.NewStyle().
			Foreground(theme.Success),

		HealthWarning: lipgloss.NewStyle().
			Foreground(theme.Warning),

		HealthCritical: lipgloss.NewStyle().
			Foreground(theme.Error),

		// Menu styles
		MenuItem: lipgloss.NewStyle().
			Padding(0, 2),

		MenuItemActive: lipgloss.NewStyle().
			Foreground(theme.Accent).
			Bold(true).
			Padding(0, 2),

		MenuShortcut: lipgloss.NewStyle().
			Foreground(theme.Info).
			Bold(true),

		// Misc styles
		Help: lipgloss.NewStyle().
			Foreground(theme.Subtle),

		StatusBar: lipgloss.NewStyle().
			Foreground(theme.Subtle).
			MarginTop(1),

		Breadcrumb: lipgloss.NewStyle().
			Foreground(theme.Accent).
			Bold(true),
	}
}

// GetTheme returns a theme by name
func GetTheme(name string) Theme {
	switch name {
	case "light":
		return LightTheme
	case "minimal":
		return MinimalTheme
	default:
		return DarkTheme
	}
}

// NextTheme cycles to the next theme
func NextTheme(current string) string {
	switch current {
	case "dark":
		return "light"
	case "light":
		return "minimal"
	default:
		return "dark"
	}
}
