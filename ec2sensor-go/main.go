package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/quanticsoul4772/ec2sensor-go/api"
	"github.com/quanticsoul4772/ec2sensor-go/config"
	"github.com/quanticsoul4772/ec2sensor-go/models"
	"github.com/quanticsoul4772/ec2sensor-go/ssh"
	"github.com/quanticsoul4772/ec2sensor-go/ui"
)

// View represents the current screen
type View int

const (
	ViewHome View = iota
	ViewOperations
	ViewHealth
	ViewHelp
	ViewConfirmDelete
	ViewConfirmDeploy
	ViewDeploying
	ViewUpgrade
	ViewUpgradeConfirm
	ViewUpgrading
	ViewEnableFeatures
	ViewEnablingFeatures
	ViewFleetManager
	ViewAddingToFleet
	ViewTrafficGenerator
	ViewTrafficStart
)

// Model is the main application state
type Model struct {
	// Configuration
	config *config.Config

	// Clients
	apiClient *api.Client
	sshClient *ssh.Client

	// UI state
	view          View
	previousView  View
	cursor        int
	multiSelect   bool
	themeName     string
	styles        ui.Styles
	width, height int

	// Data
	sensors       []*models.Sensor
	selectedIdx   int
	runningCount  int
	errorCount    int

	// Session tracking
	sessionStart time.Time
	lastRefresh  time.Time

	// Loading state
	loading       bool
	loadingMsg    string
	spinner       spinner.Model

	// Messages/errors
	statusMessage string
	errorMessage  string

	// API status
	apiOnline bool

	// Deployment state
	deploying           bool
	deployingSensorName string
	deployStartTime     time.Time
	deployStatus        string
	deployLogs          []string
	deployPhase         int    // 1=SSH port, 2=SSH service, 3=Seeding
	deployPhaseStart    time.Time

	// Upgrade state
	upgrading           bool
	upgradeStartTime    time.Time
	upgradeLogs         []string
	upgradeCurrentVersion string
	upgradeTargetVersion  string
	upgradeAvailableVersions []string
	upgradeOption       int // 1 = latest, 2 = specific
	upgradeReleaseChannel string
	upgradeAdminPassword  string

	// Enable Features state
	enablingFeatures    bool
	enableFeaturesStart time.Time
	enableFeaturesLogs  []string

	// Fleet Manager state
	addingToFleet       bool
	fleetStart          time.Time
	fleetLogs           []string

	// Delete state
	deletingSensorName string

	// Traffic Generator state
	trafficTargetIP     string
	trafficTargetPort   string
	trafficProtocol     string
	trafficPPS          string
	trafficDuration     string
	trafficInputStep    int // 0=IP, 1=port, 2=protocol, 3=pps, 4=duration
}

// Messages
type (
	sensorsLoadedMsg struct {
		sensors []*models.Sensor
		err     error
	}

	metricsLoadedMsg struct {
		sensorIdx int
		metrics   *models.SensorMetrics
		err       error
	}

	tickMsg       time.Time
	apiStatusMsg  bool
	deleteResult  struct{ err error }
	sshConnectMsg struct{ ip string }

	// Deployment messages
	deployStartedMsg struct {
		sensorName string
		err        error
	}

	deployStatusMsg struct {
		status      string
		ip          string
		isRunning   bool
		phase       int    // Current phase being checked
		phaseStatus string // Status of current phase check
		seededValue string // Value of system.seeded
		err         error
	}

	deployCompleteMsg struct {
		sensorName string
		ip         string
		err        error
	}

	// Upgrade messages
	upgradeInfoMsg struct {
		currentVersion    string
		availableVersions []string
		releaseChannel    string
		adminPassword     string
		err               error
	}

	upgradeStartedMsg struct {
		err error
	}

	upgradeProgressMsg struct {
		sshAvailable    bool
		processRunning  bool
		newVersion      string
		err             error
	}

	upgradeCompleteMsg struct {
		newVersion string
		err        error
	}

	// Enable Features messages
	enableFeaturesResultMsg struct {
		output string
		err    error
	}

	// Fleet Manager messages
	fleetResultMsg struct {
		output string
		err    error
	}
)

func initialModel(cfg *config.Config) Model {
	s := spinner.New()
	s.Spinner = spinner.Dot

	theme := ui.GetTheme(cfg.Theme)

	return Model{
		config:       cfg,
		apiClient:    api.NewClient(cfg),
		sshClient:    ssh.NewClient(cfg),
		view:         ViewHome,
		themeName:    cfg.Theme,
		styles:       ui.NewStyles(theme),
		sessionStart: time.Now(),
		lastRefresh:  time.Now(),
		spinner:      s,
		loading:      true,
		loadingMsg:   "Loading sensors...",
		apiOnline:    true,
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.loadSensors(),
		m.spinner.Tick,
		tickCmd(),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		return m.handleKeyPress(msg)

	case spinner.TickMsg:
		if m.loading || m.deploying || m.upgrading || m.enablingFeatures || m.addingToFleet {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			cmds = append(cmds, cmd)
		}

	case tickMsg:
		// If upgrading, check progress
		if m.upgrading && m.selectedIdx < len(m.sensors) {
			ip := m.sensors[m.selectedIdx].IP
			cmds = append(cmds, m.checkUpgradeProgress(ip))
		} else if m.deploying && m.deployingSensorName != "" {
			// If deploying, check status
			cmds = append(cmds, m.checkDeployStatus())
		} else {
			// Auto-refresh every 60 seconds
			if time.Since(m.lastRefresh) > 60*time.Second {
				cmds = append(cmds, m.loadSensors())
			}
			cmds = append(cmds, tickCmd())
		}

	case sensorsLoadedMsg:
		// Only clear loading if we're not in the middle of a delete operation
		if m.deletingSensorName == "" {
			m.loading = false
		}
		if msg.err != nil {
			m.errorMessage = msg.err.Error()
		} else {
			m.sensors = msg.sensors
			m.lastRefresh = time.Now()
			m.countSensors()
			// Start collecting metrics for running sensors
			for i, sensor := range m.sensors {
				if sensor.IsReady() {
					cmds = append(cmds, m.collectMetrics(i, sensor.IP))
				}
			}
		}

	case metricsLoadedMsg:
		if msg.err == nil && msg.sensorIdx < len(m.sensors) {
			m.sensors[msg.sensorIdx].Metrics = msg.metrics
			m.sensors[msg.sensorIdx].MetricsUpdated = time.Now()
		}

	case apiStatusMsg:
		m.apiOnline = bool(msg)

	case deleteResult:
		m.loading = false
		m.deletingSensorName = "" // Clear the sensor name
		if msg.err != nil {
			m.errorMessage = fmt.Sprintf("Delete failed: %v", msg.err)
			m.view = ViewHome // Go home even on error
		} else {
			m.statusMessage = "Sensor deleted successfully"
			m.view = ViewHome
			cmds = append(cmds, m.loadSensors())
		}

	case deployStartedMsg:
		if msg.err != nil {
			m.deploying = false
			m.view = ViewHome
			m.errorMessage = fmt.Sprintf("Failed to create sensor: %v", msg.err)
		} else {
			m.deployingSensorName = msg.sensorName
			m.deployLogs = append(m.deployLogs, fmt.Sprintf("✓ Sensor created: %s", shortenSensorName(msg.sensorName)))
			m.deployLogs = append(m.deployLogs, "Waiting for sensor to be ready (~20 minutes)...")
			// Start polling for status
			cmds = append(cmds, m.checkDeployStatus())
		}

	case deployStatusMsg:
		elapsed := time.Since(m.deployStartTime).Round(time.Second)
		phaseElapsed := time.Since(m.deployPhaseStart).Round(time.Second)

		if msg.err != nil {
			// Log error but continue monitoring
			m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] ⚠ %v", formatElapsed(elapsed), msg.err))
			cmds = append(cmds, tea.Tick(15*time.Second, func(t time.Time) tea.Msg {
				return tickMsg(t)
			}))
		} else {
			// Update phase tracking
			if msg.phase > m.deployPhase {
				m.deployPhase = msg.phase
				m.deployPhaseStart = time.Now()
			}

			// Build status based on phase
			switch msg.phase {
			case 0:
				// Still waiting for API to report running
				m.deployStatus = msg.status
				m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] API Status: %s", formatElapsed(elapsed), msg.status))
				cmds = append(cmds, tea.Tick(30*time.Second, func(t time.Time) tea.Msg {
					return tickMsg(t)
				}))
			case 1:
				// Phase 1: SSH port
				m.deployStatus = "Phase 1/3: SSH port"
				if msg.phaseStatus == "waiting" {
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] [Phase 1/3] Waiting for SSH port...", formatElapsed(elapsed)))
					cmds = append(cmds, tea.Tick(10*time.Second, func(t time.Time) tea.Msg {
						return tickMsg(t)
					}))
				} else {
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] [Phase 1/3] ✓ SSH port accessible (%s)", formatElapsed(elapsed), formatElapsed(phaseElapsed)))
					// Continue to phase 2 immediately
					cmds = append(cmds, m.checkDeployStatus())
				}
			case 2:
				// Phase 2: SSH service
				m.deployStatus = "Phase 2/3: SSH service"
				if msg.phaseStatus == "waiting" {
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] [Phase 2/3] Waiting for SSH service...", formatElapsed(elapsed)))
					cmds = append(cmds, tea.Tick(10*time.Second, func(t time.Time) tea.Msg {
						return tickMsg(t)
					}))
				} else {
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] [Phase 2/3] ✓ SSH service ready (%s)", formatElapsed(elapsed), formatElapsed(phaseElapsed)))
					m.deployLogs = append(m.deployLogs, "")
					m.deployLogs = append(m.deployLogs, "[Phase 3/3] Waiting for sensor seeding (system.seeded=1)...")
					m.deployLogs = append(m.deployLogs, "This can take 60+ minutes for initial seeding...")
					// Continue to phase 3 immediately
					cmds = append(cmds, m.checkDeployStatus())
				}
			case 3:
				// Phase 3: Seeding
				m.deployStatus = "Phase 3/3: Seeding"
				if msg.phaseStatus == "waiting" {
					seededInfo := ""
					if msg.seededValue != "" {
						seededInfo = fmt.Sprintf(" (system.seeded=%s)", msg.seededValue)
					}
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] [Phase 3/3] Seeding in progress%s", formatElapsed(elapsed), seededInfo))
					cmds = append(cmds, tea.Tick(15*time.Second, func(t time.Time) tea.Msg {
						return tickMsg(t)
					}))
				} else {
					// Seeding complete!
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("[%s] [Phase 3/3] ✓ Seeding complete! (%s)", formatElapsed(elapsed), formatElapsed(phaseElapsed)))
					m.deployLogs = append(m.deployLogs, "")
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("✓ Sensor is READY at %s", msg.ip))
					m.deployLogs = append(m.deployLogs, fmt.Sprintf("Total deployment time: %s", formatElapsed(elapsed)))
					cmds = append(cmds, func() tea.Msg {
						return deployCompleteMsg{sensorName: m.deployingSensorName, ip: msg.ip}
					})
				}
			}
		}

		// Keep only last 20 log lines to avoid overflow
		if len(m.deployLogs) > 20 {
			m.deployLogs = m.deployLogs[len(m.deployLogs)-20:]
		}

	case deployCompleteMsg:
		m.deploying = false
		m.loading = false
		if msg.err != nil {
			m.errorMessage = fmt.Sprintf("Deployment failed: %v", msg.err)
			m.view = ViewHome
		} else {
			m.statusMessage = fmt.Sprintf("Sensor deployed successfully at %s", msg.ip)
			m.view = ViewHome
			// Refresh sensor list
			cmds = append(cmds, m.loadSensors())
		}

	case upgradeInfoMsg:
		m.loading = false
		if msg.err != nil {
			m.errorMessage = fmt.Sprintf("Failed to get sensor info: %v", msg.err)
			m.view = ViewOperations
		} else {
			m.upgradeCurrentVersion = msg.currentVersion
			m.upgradeAvailableVersions = msg.availableVersions
			m.upgradeReleaseChannel = msg.releaseChannel
			m.upgradeAdminPassword = msg.adminPassword
			m.view = ViewUpgrade
		}

	case upgradeStartedMsg:
		if msg.err != nil {
			m.upgrading = false
			m.view = ViewOperations
			m.errorMessage = fmt.Sprintf("Upgrade failed to start: %v", msg.err)
		} else {
			m.upgradeLogs = append(m.upgradeLogs, "✓ Upgrade command executed successfully")
			m.upgradeLogs = append(m.upgradeLogs, "Monitoring upgrade progress...")
			// Start monitoring progress
			cmds = append(cmds, tea.Tick(5*time.Second, func(t time.Time) tea.Msg {
				return tickMsg(t)
			}))
		}

	case upgradeProgressMsg:
		elapsed := time.Since(m.upgradeStartTime).Round(time.Second)

		if msg.err != nil {
			m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("[%s] ⚠ Check error: %v", formatElapsed(elapsed), msg.err))
			// Continue monitoring even on error - no timeout
		} else if !msg.sshAvailable {
			m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("[%s] Sensor rebooting... (SSH unavailable)", formatElapsed(elapsed)))
		} else if msg.processRunning {
			m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("[%s] Upgrade in progress...", formatElapsed(elapsed)))
		} else if msg.newVersion != "" && msg.newVersion != "unknown" {
			// Upgrade complete!
			m.upgradeLogs = append(m.upgradeLogs, "")
			if msg.newVersion != m.upgradeCurrentVersion {
				m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("✓ Upgraded from %s to %s", m.upgradeCurrentVersion, msg.newVersion))
			} else {
				m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("✓ Upgrade complete: %s", msg.newVersion))
			}
			m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("Completed in %s", formatElapsed(elapsed)))
			m.upgrading = false
			return m, nil
		} else {
			m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("[%s] Verifying...", formatElapsed(elapsed)))
		}

		// Keep only last 15 log lines
		if len(m.upgradeLogs) > 15 {
			m.upgradeLogs = m.upgradeLogs[len(m.upgradeLogs)-15:]
		}

		// Continue monitoring indefinitely (every 10 seconds) - no timeout
		cmds = append(cmds, tea.Tick(10*time.Second, func(t time.Time) tea.Msg {
			return tickMsg(t)
		}))

	case upgradeCompleteMsg:
		m.upgrading = false
		if msg.err != nil {
			m.upgradeLogs = append(m.upgradeLogs, "")
			m.upgradeLogs = append(m.upgradeLogs, fmt.Sprintf("✗ Upgrade failed: %v", msg.err))
		}

	case enableFeaturesResultMsg:
		m.enablingFeatures = false
		elapsed := time.Since(m.enableFeaturesStart).Round(time.Second)
		if msg.err != nil {
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, fmt.Sprintf("✗ Failed: %v", msg.err))
			if msg.output != "" {
				// Add last few lines of output for debugging
				lines := strings.Split(msg.output, "\n")
				if len(lines) > 5 {
					lines = lines[len(lines)-5:]
				}
				for _, line := range lines {
					if strings.TrimSpace(line) != "" {
						m.enableFeaturesLogs = append(m.enableFeaturesLogs, "  "+line)
					}
				}
			}
		} else {
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, fmt.Sprintf("✓ Features enabled successfully in %s", formatElapsed(elapsed)))
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "Enabled features:")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "  ✓ HTTP access")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "  ✓ YARA engine")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "  ✓ Suricata IDS")
			m.enableFeaturesLogs = append(m.enableFeaturesLogs, "  ✓ SmartPCAP")
		}

	case fleetResultMsg:
		m.addingToFleet = false
		elapsed := time.Since(m.fleetStart).Round(time.Second)
		if msg.err != nil {
			m.fleetLogs = append(m.fleetLogs, "")
			m.fleetLogs = append(m.fleetLogs, fmt.Sprintf("✗ Failed: %v", msg.err))
			if msg.output != "" {
				lines := strings.Split(msg.output, "\n")
				if len(lines) > 5 {
					lines = lines[len(lines)-5:]
				}
				for _, line := range lines {
					if strings.TrimSpace(line) != "" {
						m.fleetLogs = append(m.fleetLogs, "  "+line)
					}
				}
			}
		} else {
			m.fleetLogs = append(m.fleetLogs, "")
			m.fleetLogs = append(m.fleetLogs, fmt.Sprintf("✓ Sensor added to fleet manager in %s", formatElapsed(elapsed)))
		}

	case trafficConfigResultMsg:
		m.loading = false
		if msg.err != nil {
			m.errorMessage = fmt.Sprintf("Traffic generator config failed: %v", msg.err)
		} else {
			m.statusMessage = "Traffic generator configured successfully"
		}

	case sshConnectMsg:
		// Execute SSH in a subprocess
		return m, tea.ExecProcess(m.sshCommand(msg.ip), func(err error) tea.Msg {
			return nil
		})
	}

	return m, tea.Batch(cmds...)
}

func (m Model) View() string {
	if m.loading {
		return m.renderLoading()
	}

	switch m.view {
	case ViewHome:
		return m.renderHome()
	case ViewOperations:
		return m.renderOperations()
	case ViewHealth:
		return m.renderHealth()
	case ViewHelp:
		return ui.RenderHelp(m.styles, m.helpContext())
	case ViewConfirmDelete:
		return m.renderConfirmDelete()
	case ViewConfirmDeploy:
		return m.renderConfirmDeploy()
	case ViewDeploying:
		return m.renderDeploying()
	case ViewUpgrade:
		return m.renderUpgrade()
	case ViewUpgradeConfirm:
		return m.renderUpgradeConfirm()
	case ViewUpgrading:
		return m.renderUpgrading()
	case ViewEnableFeatures:
		return m.renderEnableFeatures()
	case ViewEnablingFeatures:
		return m.renderEnablingFeatures()
	case ViewFleetManager:
		return m.renderFleetManager()
	case ViewAddingToFleet:
		return m.renderAddingToFleet()
	case ViewTrafficGenerator:
		return m.renderTrafficGenerator()
	case ViewTrafficStart:
		return m.renderTrafficStart()
	default:
		return m.renderHome()
	}
}

// Key handling
func (m Model) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global shortcuts
	switch msg.String() {
	case "ctrl+c", "q":
		if m.view == ViewHome {
			return m, tea.Quit
		}
		m.view = ViewHome
		return m, nil

	case "?":
		m.previousView = m.view
		m.view = ViewHelp
		return m, nil

	case "t":
		// Cycle theme
		m.themeName = ui.NextTheme(m.themeName)
		m.styles = ui.NewStyles(ui.GetTheme(m.themeName))
		return m, nil
	}

	// Handle help view
	if m.view == ViewHelp {
		m.view = m.previousView
		return m, nil
	}

	// Handle confirm delete view
	if m.view == ViewConfirmDelete {
		return m.handleConfirmDelete(msg)
	}

	// Handle confirm deploy view
	if m.view == ViewConfirmDeploy {
		return m.handleConfirmDeploy(msg)
	}

	// Handle deploying view
	if m.view == ViewDeploying {
		return m.handleDeployingKeys(msg)
	}

	// Handle upgrade views
	if m.view == ViewUpgrade {
		return m.handleUpgradeKeys(msg)
	}
	if m.view == ViewUpgradeConfirm {
		return m.handleUpgradeConfirmKeys(msg)
	}
	if m.view == ViewUpgrading {
		return m.handleUpgradingKeys(msg)
	}

	// Handle enable features views
	if m.view == ViewEnableFeatures {
		return m.handleEnableFeaturesKeys(msg)
	}
	if m.view == ViewEnablingFeatures {
		return m.handleEnablingFeaturesKeys(msg)
	}

	// Handle fleet manager views
	if m.view == ViewFleetManager {
		return m.handleFleetManagerKeys(msg)
	}
	if m.view == ViewAddingToFleet {
		return m.handleAddingToFleetKeys(msg)
	}

	// Handle traffic generator views
	if m.view == ViewTrafficGenerator {
		return m.handleTrafficGeneratorKeys(msg)
	}
	if m.view == ViewTrafficStart {
		return m.handleTrafficStartKeys(msg)
	}

	// View-specific handling
	switch m.view {
	case ViewHome:
		return m.handleHomeKeys(msg)
	case ViewOperations:
		return m.handleOperationsKeys(msg)
	case ViewHealth:
		return m.handleHealthKeys(msg)
	}

	return m, nil
}

func (m Model) handleHomeKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.sensors)-1 {
			m.cursor++
		}
	case "enter":
		if len(m.sensors) > 0 && m.cursor < len(m.sensors) {
			// Clear messages when entering operations
			m.errorMessage = ""
			m.statusMessage = ""
			m.selectedIdx = m.cursor
			m.view = ViewOperations
		}
	case "r":
		// Clear any error messages on refresh
		m.errorMessage = ""
		m.statusMessage = ""
		m.loading = true
		m.loadingMsg = "Refreshing sensors..."
		return m, tea.Batch(m.loadSensors(), m.spinner.Tick)
	case "n":
		m.view = ViewConfirmDeploy
	case "m":
		m.multiSelect = !m.multiSelect
	case " ":
		if m.multiSelect && m.cursor < len(m.sensors) {
			m.sensors[m.cursor].Selected = !m.sensors[m.cursor].Selected
		}
	case "1", "2", "3", "4", "5", "6", "7", "8", "9":
		idx, _ := strconv.Atoi(msg.String())
		idx-- // Convert to 0-indexed
		if idx < len(m.sensors) {
			if m.multiSelect {
				m.sensors[idx].Selected = !m.sensors[idx].Selected
				m.cursor = idx
			} else {
				// Clear messages when entering operations
				m.errorMessage = ""
				m.statusMessage = ""
				m.selectedIdx = idx
				m.cursor = idx
				m.view = ViewOperations
			}
		}
	}
	return m, nil
}

func (m Model) handleOperationsKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.selectedIdx >= len(m.sensors) {
		m.errorMessage = "Sensor no longer available. Press 'r' to refresh."
		m.view = ViewHome
		return m, nil
	}

	sensor := m.sensors[m.selectedIdx]
	
	// Check if sensor was deleted
	if sensor.Deleted || sensor.Status == models.StatusDeleted {
		m.errorMessage = fmt.Sprintf("Sensor '%s' was deleted. Removing from list.", sensor.ShortID())
		// Remove from .sensors file
		removeSensorFromFile(m.config.SensorsFile, sensor.Name)
		m.view = ViewHome
		return m, m.loadSensors()
	}

	switch msg.String() {
	case "b", "esc":
		// Clear any error messages when leaving operations view
		m.errorMessage = ""
		m.view = ViewHome
	case "c", "1":
		if sensor.IsReady() {
			return m, func() tea.Msg {
				return sshConnectMsg{ip: sensor.IP}
			}
		}
		m.errorMessage = fmt.Sprintf("Cannot connect - sensor status is %s", sensor.Status)
	case "f", "2":
		if sensor.IsReady() {
			m.view = ViewEnableFeatures
		} else {
			m.errorMessage = fmt.Sprintf("Cannot enable features - sensor status is %s", sensor.Status)
		}
	case "3":
		if sensor.IsReady() {
			m.view = ViewFleetManager
		} else {
			m.errorMessage = fmt.Sprintf("Cannot add to fleet - sensor status is %s", sensor.Status)
		}
	case "4":
		if sensor.IsReady() {
			// Initialize traffic generator defaults
			m.trafficTargetIP = ""
			m.trafficTargetPort = "5555"
			m.trafficProtocol = "udp"
			m.trafficPPS = "1000"
			m.trafficDuration = "0"
			m.trafficInputStep = 0
			m.view = ViewTrafficGenerator
		} else {
			m.errorMessage = fmt.Sprintf("Cannot configure traffic - sensor status is %s", sensor.Status)
		}
	case "u", "5":
		if sensor.IsReady() {
			// Start loading upgrade info
			m.loading = true
			m.loadingMsg = "Reading sensor configuration..."
			return m, tea.Batch(
				m.loadUpgradeInfo(sensor.IP),
				m.spinner.Tick,
			)
		} else {
			m.errorMessage = fmt.Sprintf("Cannot upgrade - sensor status is %s", sensor.Status)
		}
	case "d", "6":
		m.deletingSensorName = sensor.Name
		m.view = ViewConfirmDelete
	case "h", "7":
		if sensor.IsReady() {
			m.view = ViewHealth
		} else {
			m.errorMessage = fmt.Sprintf("Cannot view health - sensor status is %s", sensor.Status)
		}
	}
	return m, nil
}

func (m Model) handleHealthKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "b", "esc", "enter":
		m.view = ViewOperations
	}
	return m, nil
}

func (m Model) handleConfirmDelete(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y":
		if m.deletingSensorName != "" {
			m.loading = true
			m.loadingMsg = "Deleting sensor..."
			return m, tea.Batch(
				m.deleteSensor(m.deletingSensorName),
				m.spinner.Tick,
			)
		}
		// Fallback: no sensor name stored
		m.errorMessage = "No sensor selected for deletion"
		m.view = ViewHome
	case "n", "N", "esc":
		m.errorMessage = ""
		m.deletingSensorName = ""
		m.view = ViewHome
	}
	return m, nil
}

func (m Model) handleConfirmDeploy(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y":
		// Start deployment
		m.view = ViewDeploying
		m.deploying = true
		m.deployStartTime = time.Now()
		m.deployPhaseStart = time.Now()
		m.deployStatus = "creating"
		m.deployPhase = 0
		m.deployLogs = []string{"Creating new sensor..."}
		return m, tea.Batch(
			m.createSensor(),
			m.spinner.Tick,
		)
	case "n", "N", "esc":
		m.view = ViewHome
	}
	return m, nil
}

func (m Model) handleDeployingKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if !m.deploying {
		// Deployment complete - any key returns home
		m.view = ViewHome
		return m, m.loadSensors()
	}

	switch msg.String() {
	case "esc":
		// Allow canceling (sensor will still be created, but we go back to home)
		m.deploying = false
		m.view = ViewHome
		m.statusMessage = "Deployment continuing in background. Refresh to see status."
	}
	return m, nil
}

func (m Model) handleUpgradeKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "1":
		// Upgrade to latest
		if len(m.upgradeAvailableVersions) == 0 {
			m.errorMessage = "No updates available via corelight-client"
			return m, nil
		}
		m.upgradeOption = 1
		m.upgradeTargetVersion = "latest"
		m.view = ViewUpgradeConfirm
	case "2":
		// Upgrade to specific version - for now, prompt in confirm view
		m.upgradeOption = 2
		m.upgradeTargetVersion = "" // Will be set in confirm view
		m.view = ViewUpgradeConfirm
	case "3", "b", "esc":
		m.view = ViewOperations
	}
	return m, nil
}

func (m Model) handleUpgradeConfirmKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y":
		if m.selectedIdx >= len(m.sensors) {
			m.view = ViewOperations
			return m, nil
		}
		sensor := m.sensors[m.selectedIdx]
		
		// For specific version upgrade, use current version if not set
		if m.upgradeOption == 2 && m.upgradeTargetVersion == "" {
			m.upgradeTargetVersion = m.upgradeCurrentVersion
		}
		
		// Start the upgrade
		m.view = ViewUpgrading
		m.upgrading = true
		m.upgradeStartTime = time.Now()
		
		if m.upgradeOption == 1 {
			m.upgradeLogs = []string{"Starting upgrade to latest version...", "Press ESC to exit monitoring..."}
		} else {
			m.upgradeLogs = []string{fmt.Sprintf("Starting upgrade to version %s...", m.upgradeTargetVersion), "Press ESC to exit monitoring..."}
		}
		
		return m, tea.Batch(
			m.runUpgrade(sensor.IP),
			m.spinner.Tick,
		)
	case "n", "N", "esc":
		m.view = ViewUpgrade
	}
	return m, nil
}

func (m Model) handleUpgradingKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if !m.upgrading {
		// Upgrade complete - any key returns to operations
		m.view = ViewOperations
		return m, nil
	}

	switch msg.String() {
	case "esc":
		m.upgrading = false
		m.view = ViewOperations
		m.statusMessage = "Upgrade continuing in background."
	}
	return m, nil
}

// Enable Features handlers
func (m Model) handleEnableFeaturesKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y":
		if m.selectedIdx >= len(m.sensors) {
			m.view = ViewOperations
			return m, nil
		}
		sensor := m.sensors[m.selectedIdx]
		
		// Start enabling features
		m.view = ViewEnablingFeatures
		m.enablingFeatures = true
		m.enableFeaturesStart = time.Now()
		m.enableFeaturesLogs = []string{
			fmt.Sprintf("Connecting to %s...", sensor.IP),
			"Running enable_sensor_features.sh...",
			"",
			"This enables:",
			"  • HTTP access (API/UI)",
			"  • YARA engine",
			"  • Suricata IDS",
			"  • SmartPCAP",
			"",
		}
		
		return m, tea.Batch(
			m.runEnableFeatures(sensor.IP),
			m.spinner.Tick,
		)
	case "n", "N", "esc":
		m.view = ViewOperations
	}
	return m, nil
}

func (m Model) handleEnablingFeaturesKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if !m.enablingFeatures {
		// Operation complete - any key returns to operations
		m.view = ViewOperations
		return m, nil
	}

	switch msg.String() {
	case "esc":
		m.enablingFeatures = false
		m.view = ViewOperations
		m.statusMessage = "Enable features continuing in background."
	}
	return m, nil
}

// Fleet Manager handlers
func (m Model) handleFleetManagerKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y":
		if m.selectedIdx >= len(m.sensors) {
			m.view = ViewOperations
			return m, nil
		}
		sensor := m.sensors[m.selectedIdx]
		
		// Start adding to fleet
		m.view = ViewAddingToFleet
		m.addingToFleet = true
		m.fleetStart = time.Now()
		m.fleetLogs = []string{
			fmt.Sprintf("Connecting to %s...", sensor.IP),
			"Running prepare_p1_automation.sh...",
			"",
		}
		
		return m, tea.Batch(
			m.runAddToFleet(sensor.IP),
			m.spinner.Tick,
		)
	case "n", "N", "esc":
		m.view = ViewOperations
	}
	return m, nil
}

func (m Model) handleAddingToFleetKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if !m.addingToFleet {
		// Operation complete - any key returns to operations
		m.view = ViewOperations
		return m, nil
	}

	switch msg.String() {
	case "esc":
		m.addingToFleet = false
		m.view = ViewOperations
		m.statusMessage = "Fleet registration continuing in background."
	}
	return m, nil
}

// Traffic Generator handlers
func (m Model) handleTrafficGeneratorKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "1":
		// Configure sensor as traffic generator
		if m.selectedIdx < len(m.sensors) {
			sensor := m.sensors[m.selectedIdx]
			m.loading = true
			m.loadingMsg = "Configuring traffic generator..."
			return m, tea.Batch(
				m.runConfigureTrafficGenerator(sensor.IP),
				m.spinner.Tick,
			)
		}
	case "2":
		// Start traffic generation - go to input view
		m.trafficInputStep = 0
		m.trafficTargetIP = ""
		m.view = ViewTrafficStart
	case "3":
		// Stop traffic generation
		if m.selectedIdx < len(m.sensors) {
			sensor := m.sensors[m.selectedIdx]
			m.sshClient.StopTrafficGeneration(sensor.IP)
			m.statusMessage = "Traffic generation stopped"
		}
	case "4":
		// View traffic statistics
		if m.selectedIdx < len(m.sensors) {
			sensor := m.sensors[m.selectedIdx]
			status, _ := m.sshClient.GetTrafficStatus(sensor.IP)
			if status == "" {
				m.statusMessage = "No traffic generation running"
			} else {
				m.statusMessage = "Traffic: " + status
			}
		}
	case "5", "b", "esc":
		m.view = ViewOperations
	}
	return m, nil
}

func (m Model) handleTrafficStartKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	key := msg.String()
	
	switch key {
	case "esc":
		m.view = ViewTrafficGenerator
		return m, nil
	case "enter":
		// Move to next step or start traffic
		switch m.trafficInputStep {
		case 0:
			// Validate IP
			if m.trafficTargetIP == "" {
				m.errorMessage = "Target IP is required"
				return m, nil
			}
			m.trafficInputStep = 1
		case 1:
			if m.trafficTargetPort == "" {
				m.trafficTargetPort = "5555"
			}
			m.trafficInputStep = 2
		case 2:
			if m.trafficProtocol == "" {
				m.trafficProtocol = "udp"
			}
			m.trafficInputStep = 3
		case 3:
			if m.trafficPPS == "" {
				m.trafficPPS = "1000"
			}
			m.trafficInputStep = 4
		case 4:
			if m.trafficDuration == "" {
				m.trafficDuration = "0"
			}
			// All inputs collected, start traffic
			if m.selectedIdx < len(m.sensors) {
				sensor := m.sensors[m.selectedIdx]
				go m.sshClient.StartTrafficGeneration(
					sensor.IP,
					m.trafficTargetIP,
					m.trafficTargetPort,
					m.trafficProtocol,
					m.trafficPPS,
					m.trafficDuration,
				)
				m.statusMessage = fmt.Sprintf("Traffic generation started to %s:%s", m.trafficTargetIP, m.trafficTargetPort)
			}
			m.view = ViewTrafficGenerator
		}
	case "backspace":
		// Handle backspace for current input
		switch m.trafficInputStep {
		case 0:
			if len(m.trafficTargetIP) > 0 {
				m.trafficTargetIP = m.trafficTargetIP[:len(m.trafficTargetIP)-1]
			}
		case 1:
			if len(m.trafficTargetPort) > 0 {
				m.trafficTargetPort = m.trafficTargetPort[:len(m.trafficTargetPort)-1]
			}
		case 2:
			if len(m.trafficProtocol) > 0 {
				m.trafficProtocol = m.trafficProtocol[:len(m.trafficProtocol)-1]
			}
		case 3:
			if len(m.trafficPPS) > 0 {
				m.trafficPPS = m.trafficPPS[:len(m.trafficPPS)-1]
			}
		case 4:
			if len(m.trafficDuration) > 0 {
				m.trafficDuration = m.trafficDuration[:len(m.trafficDuration)-1]
			}
		}
	default:
		// Add character to current input
		if len(key) == 1 {
			switch m.trafficInputStep {
			case 0:
				if (key >= "0" && key <= "9") || key == "." {
					m.trafficTargetIP += key
				}
			case 1:
				if key >= "0" && key <= "9" {
					m.trafficTargetPort += key
				}
			case 2:
				m.trafficProtocol += key
			case 3:
				if key >= "0" && key <= "9" {
					m.trafficPPS += key
				}
			case 4:
				if key >= "0" && key <= "9" {
					m.trafficDuration += key
				}
			}
		}
	}
	return m, nil
}

// Rendering functions
func (m Model) renderLoading() string {
	return fmt.Sprintf("\n\n  %s %s\n", m.spinner.View(), m.loadingMsg)
}

func (m Model) renderHome() string {
	var b strings.Builder

	// Header
	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "EC2 SENSOR MANAGER", "v2.0"))
	b.WriteString("\n")

	// Breadcrumb
	b.WriteString(ui.RenderBreadcrumb(m.styles, "Home"))
	b.WriteString("\n\n")

	// Messages
	if m.errorMessage != "" {
		b.WriteString(ui.RenderMessage(m.styles, "error", m.errorMessage, ""))
		b.WriteString("\n")
	}
	if m.statusMessage != "" {
		b.WriteString(ui.RenderMessage(m.styles, "info", m.statusMessage, ""))
		b.WriteString("\n")
	}

	// Section header
	b.WriteString(ui.RenderSection(m.styles, "Available Sensors"))
	b.WriteString("\n\n")

	// Sensor table
	if len(m.sensors) == 0 {
		b.WriteString(ui.RenderMessage(m.styles, "warning", "No sensors found", "Deploy a new sensor to get started"))
	} else {
		b.WriteString(ui.RenderSensorTable(m.styles, m.sensors, m.cursor, m.multiSelect))
	}
	b.WriteString("\n")

	// Status bar
	b.WriteString(ui.RenderStatusBar(
		m.styles,
		m.runningCount,
		m.errorCount,
		time.Since(m.sessionStart),
		time.Since(m.lastRefresh),
	))
	b.WriteString("\n\n")

	// Options
	b.WriteString(ui.RenderSection(m.styles, "Options"))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "n", "Deploy NEW sensor", "Create and configure new sensor (~20 min)", false))
	b.WriteString("\n\n")

	// Shortcuts
	b.WriteString(ui.RenderSection(m.styles, "Shortcuts"))
	b.WriteString("\n")
	b.WriteString(ui.RenderShortcuts(m.styles, ui.MainShortcuts()))
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderOperations() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	// Header
	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "SENSOR OPERATIONS", sensor.ShortID()))
	b.WriteString("\n")

	// Breadcrumb
	b.WriteString(ui.RenderBreadcrumb(m.styles, "Home", "Sensors", sensor.ShortID()))
	b.WriteString("\n\n")

	// Messages
	if m.errorMessage != "" {
		b.WriteString(ui.RenderMessage(m.styles, "error", m.errorMessage, ""))
		b.WriteString("\n")
	}
	if m.statusMessage != "" {
		b.WriteString(ui.RenderMessage(m.styles, "info", m.statusMessage, ""))
		b.WriteString("\n")
	}

	// Sensor info
	b.WriteString(ui.RenderSection(m.styles, "Sensor Information"))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor ID", sensor.ShortID()))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Status", ui.RenderStatusIcon(m.styles, sensor.Status)))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n")
	if sensor.BrolinVersion != "" {
		b.WriteString(ui.RenderKeyValue(m.styles, "Version", sensor.BrolinVersion))
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Operations menu
	b.WriteString(ui.RenderSection(m.styles, "Operations"))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "1", "Connect (SSH)", "Open SSH terminal session", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "2", "Enable features", "HTTP, YARA, Suricata, SmartPCAP", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "3", "Add to fleet manager", "Register with fleet management", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "4", "Traffic Generator", "Configure traffic generation", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "5", "Upgrade sensor", "Update to latest version", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "6", "Delete sensor", "Permanently remove sensor", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "7", "Health Dashboard", "Detailed health & service view", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "8", "Back to sensor list", "", false))
	b.WriteString("\n\n")

	// Shortcuts
	b.WriteString(ui.RenderSection(m.styles, "Shortcuts"))
	b.WriteString("\n")
	b.WriteString(ui.RenderShortcuts(m.styles, ui.OperationsShortcuts()))
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderHealth() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	// Header
	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "HEALTH DASHBOARD", sensor.ShortID()))
	b.WriteString("\n")

	// Breadcrumb
	b.WriteString(ui.RenderBreadcrumb(m.styles, "Home", "Sensors", sensor.ShortID(), "Health"))
	b.WriteString("\n\n")

	// Overview
	b.WriteString(ui.RenderSection(m.styles, "Overview"))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor ID", sensor.ShortID()))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Status", ui.RenderStatusIcon(m.styles, sensor.Status)))
	b.WriteString("\n\n")

	// Resource usage with bars
	b.WriteString(ui.RenderSection(m.styles, "Resource Usage"))
	b.WriteString("\n")

	if sensor.HasMetrics() {
		// CPU
		b.WriteString(fmt.Sprintf("  CPU:    %s %s\n",
			ui.RenderProgressBar(m.styles, sensor.Metrics.CPU, 100, 20),
			ui.RenderHealthValue(m.styles, sensor.Metrics.CPU)))

		// Memory
		b.WriteString(fmt.Sprintf("  Memory: %s %s\n",
			ui.RenderProgressBar(m.styles, sensor.Metrics.Memory, 100, 20),
			ui.RenderHealthValue(m.styles, sensor.Metrics.Memory)))

		// Disk
		b.WriteString(fmt.Sprintf("  Disk:   %s %s\n",
			ui.RenderProgressBar(m.styles, sensor.Metrics.Disk, 100, 20),
			ui.RenderHealthValue(m.styles, sensor.Metrics.Disk)))

		b.WriteString("\n")
		b.WriteString(ui.RenderKeyValue(m.styles, "Running Services", fmt.Sprintf("%d", sensor.Metrics.Pods)))
		b.WriteString("\n")
	} else {
		b.WriteString(m.styles.Help.Render("  Metrics not available"))
		b.WriteString("\n")
	}

	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  Press b or Enter to return..."))
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderConfirmDelete() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "CONFIRM DELETE", ""))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderMessage(m.styles, "warning", "This action cannot be undone!", ""))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor ID", sensor.ShortID()))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n\n")

	b.WriteString(fmt.Sprintf("  Delete this sensor permanently? %s / %s\n",
		m.styles.Success.Render("[y]es"),
		m.styles.Error.Render("[n]o")))

	return b.String()
}

func (m Model) renderConfirmDeploy() string {
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "DEPLOY NEW SENSOR", ""))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderSection(m.styles, "Deployment Information"))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Branch", "testing"))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Team", "cicd"))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Est. Time", "~20 minutes"))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderMessage(m.styles, "info", "A new EC2 sensor will be created and automatically configured.", ""))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  Features will be auto-enabled once the sensor is ready."))
	b.WriteString("\n\n")

	b.WriteString(fmt.Sprintf("  Deploy new sensor? %s / %s\n",
		m.styles.Success.Render("[y]es"),
		m.styles.Error.Render("[n]o")))

	return b.String()
}

func (m Model) renderDeploying() string {
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "DEPLOYING SENSOR", ""))
	b.WriteString("\n\n")

	// Show elapsed time - no timeout
	elapsed := time.Since(m.deployStartTime).Round(time.Second)
	b.WriteString(ui.RenderKeyValue(m.styles, "Elapsed", formatElapsed(elapsed)))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Status", m.deployStatus))
	b.WriteString("\n")
	if m.deployingSensorName != "" {
		b.WriteString(ui.RenderKeyValue(m.styles, "Sensor", shortenSensorName(m.deployingSensorName)))
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Phase progress indicator
	b.WriteString(ui.RenderSection(m.styles, "Deployment Progress"))
	b.WriteString("\n")
	
	// Show phase progress
	phases := []struct {
		num  int
		name string
	}{
		{1, "SSH Port"},
		{2, "SSH Service"},
		{3, "Seeding (60+ min)"},
	}
	
	for _, p := range phases {
		var icon, style string
		if m.deployPhase > p.num {
			icon = "✓"
			style = "success"
		} else if m.deployPhase == p.num {
			icon = m.spinner.View()
			style = "info"
		} else {
			icon = "○"
			style = "help"
		}
		
		line := fmt.Sprintf("  %s Phase %d: %s", icon, p.num, p.name)
		switch style {
		case "success":
			b.WriteString(m.styles.Success.Render(line))
		case "info":
			b.WriteString(m.styles.Info.Render(line))
		default:
			b.WriteString(m.styles.Help.Render(line))
		}
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Status indicator
	if m.deploying {
		if m.deployPhase == 0 {
			b.WriteString(fmt.Sprintf("  %s Waiting for sensor to start...\n", m.spinner.View()))
		} else if m.deployPhase == 3 {
			b.WriteString(fmt.Sprintf("  %s Seeding in progress (this takes 60+ minutes)...\n", m.spinner.View()))
		} else {
			b.WriteString(fmt.Sprintf("  %s Deployment in progress...\n", m.spinner.View()))
		}
	} else {
		b.WriteString(m.styles.Success.Render("  ✓ Deployment complete"))
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Show deployment logs
	b.WriteString(ui.RenderSection(m.styles, "Deployment Log"))
	b.WriteString("\n")
	for _, log := range m.deployLogs {
		if strings.HasPrefix(log, "✓") {
			b.WriteString(m.styles.Success.Render("  " + log))
		} else if strings.HasPrefix(log, "⚠") || strings.HasPrefix(log, "✗") {
			b.WriteString(m.styles.Error.Render("  " + log))
		} else if strings.HasPrefix(log, "[") {
			b.WriteString(m.styles.Info.Render("  " + log))
		} else if strings.HasPrefix(log, "This can take") {
			b.WriteString(m.styles.Warning.Render("  " + log))
		} else {
			b.WriteString(m.styles.Help.Render("  " + log))
		}
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Help text - make ESC prominent
	if m.deploying {
		b.WriteString(m.styles.Warning.Render("  ⚠ Press ESC to exit monitoring (deployment continues in background)"))
	} else {
		b.WriteString(m.styles.Help.Render("  Press any key to return to home"))
	}
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderUpgrade() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	// Header
	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "SENSOR UPGRADE", sensor.ShortID()))
	b.WriteString("\n")

	// Breadcrumb
	b.WriteString(ui.RenderBreadcrumb(m.styles, "Home", "Sensors", sensor.ShortID(), "Upgrade"))
	b.WriteString("\n\n")

	// Current sensor info
	b.WriteString(ui.RenderSection(m.styles, "Sensor Information"))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Current Version", m.upgradeCurrentVersion))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Release Channel", m.upgradeReleaseChannel))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n\n")

	// Available versions
	b.WriteString(ui.RenderSection(m.styles, "Available Versions"))
	b.WriteString("\n")
	if len(m.upgradeAvailableVersions) == 0 {
		b.WriteString(m.styles.Success.Render("  ✓ Sensor is up to date!"))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("  No newer versions available via corelight-client"))
		b.WriteString("\n")
	} else {
		for _, v := range m.upgradeAvailableVersions {
			b.WriteString(fmt.Sprintf("  %s %s\n", m.styles.Info.Render("•"), v))
		}
	}
	b.WriteString("\n")

	// Upgrade options
	b.WriteString(ui.RenderSection(m.styles, "Upgrade Options"))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "1", "Upgrade to LATEST version", "corelight-client updates apply", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "2", "Upgrade to SPECIFIC version", "broala-update-repository", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "3", "Back", "Return to operations menu", false))
	b.WriteString("\n\n")

	b.WriteString(m.styles.Help.Render("  Select upgrade option [1-3]"))
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderUpgradeConfirm() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "CONFIRM UPGRADE", ""))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderMessage(m.styles, "warning", "Sensor will restart and be unavailable for 2-5 minutes!", ""))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor", sensor.ShortID()))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Current Version", m.upgradeCurrentVersion))
	b.WriteString("\n")

	if m.upgradeOption == 1 {
		b.WriteString(ui.RenderKeyValue(m.styles, "Target", "Latest available version"))
		b.WriteString("\n")
		b.WriteString(ui.RenderKeyValue(m.styles, "Method", "corelight-client updates apply"))
	} else {
		// For specific version upgrade
		targetVersion := m.upgradeTargetVersion
		if targetVersion == "" {
			targetVersion = "(will use current: " + m.upgradeCurrentVersion + ")"
		}
		b.WriteString(ui.RenderKeyValue(m.styles, "Target Version", targetVersion))
		b.WriteString("\n")
		b.WriteString(ui.RenderKeyValue(m.styles, "Method", "broala-update-repository"))
	}
	b.WriteString("\n\n")

	b.WriteString(fmt.Sprintf("  Proceed with upgrade? %s / %s\n",
		m.styles.Success.Render("[y]es"),
		m.styles.Error.Render("[n]o")))

	return b.String()
}

func (m Model) renderUpgrading() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "UPGRADING SENSOR", sensor.ShortID()))
	b.WriteString("\n\n")

	// Progress info - no timeout, just elapsed time
	elapsed := time.Since(m.upgradeStartTime).Round(time.Second)

	b.WriteString(ui.RenderKeyValue(m.styles, "Elapsed", formatElapsed(elapsed)))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor", sensor.IP))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "From Version", m.upgradeCurrentVersion))
	b.WriteString("\n\n")

	// Spinner if still upgrading (no progress bar since no timeout)
	b.WriteString(ui.RenderSection(m.styles, "Status"))
	b.WriteString("\n")
	if m.upgrading {
		b.WriteString(fmt.Sprintf("  %s Upgrade in progress...\n", m.spinner.View()))
	} else {
		b.WriteString(m.styles.Success.Render("  ✓ Monitoring complete"))
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Upgrade logs
	b.WriteString(ui.RenderSection(m.styles, "Upgrade Log"))
	b.WriteString("\n")
	for _, log := range m.upgradeLogs {
		if strings.HasPrefix(log, "✓") {
			b.WriteString(m.styles.Success.Render("  " + log))
		} else if strings.HasPrefix(log, "⚠") || strings.HasPrefix(log, "✗") {
			b.WriteString(m.styles.Error.Render("  " + log))
		} else if strings.HasPrefix(log, "[") {
			b.WriteString(m.styles.Info.Render("  " + log))
		} else {
			b.WriteString(m.styles.Help.Render("  " + log))
		}
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Help text - make ESC prominent
	if m.upgrading {
		b.WriteString(m.styles.Warning.Render("  ⚠ Press ESC to exit monitoring (upgrade continues in background)"))
	} else {
		b.WriteString(m.styles.Help.Render("  Press any key to return to operations"))
	}
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderEnableFeatures() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "ENABLE FEATURES", sensor.ShortID()))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderSection(m.styles, "Features to Enable"))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  • HTTP access (API/UI)"))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  • YARA engine"))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  • Suricata IDS"))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  • SmartPCAP"))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor", sensor.ShortID()))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderMessage(m.styles, "info", "This will configure sensor features via SSH.", ""))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  Configuration takes 1-2 minutes to apply."))
	b.WriteString("\n\n")

	b.WriteString(fmt.Sprintf("  Enable features? %s / %s\n",
		m.styles.Success.Render("[y]es"),
		m.styles.Error.Render("[n]o")))

	return b.String()
}

func (m Model) renderEnablingFeatures() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "ENABLING FEATURES", sensor.ShortID()))
	b.WriteString("\n\n")

	// Show elapsed time
	elapsed := time.Since(m.enableFeaturesStart).Round(time.Second)
	b.WriteString(ui.RenderKeyValue(m.styles, "Elapsed", formatElapsed(elapsed)))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n\n")

	// Progress indicator
	b.WriteString(ui.RenderSection(m.styles, "Progress"))
	b.WriteString("\n")

	if m.enablingFeatures {
		b.WriteString(fmt.Sprintf("  %s Enabling features...\n", m.spinner.View()))
	}
	b.WriteString("\n")

	// Show logs
	b.WriteString(ui.RenderSection(m.styles, "Log"))
	b.WriteString("\n")
	for _, log := range m.enableFeaturesLogs {
		if strings.HasPrefix(log, "✓") {
			b.WriteString(m.styles.Success.Render("  " + log))
		} else if strings.HasPrefix(log, "✗") || strings.HasPrefix(log, "⚠") {
			b.WriteString(m.styles.Error.Render("  " + log))
		} else {
			b.WriteString(m.styles.Help.Render("  " + log))
		}
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Help text
	if m.enablingFeatures {
		b.WriteString(m.styles.Help.Render("  Press ESC to return (operation will continue in background)"))
	} else {
		b.WriteString(m.styles.Help.Render("  Press any key to return to operations"))
	}
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderFleetManager() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "ADD TO FLEET MANAGER", sensor.ShortID()))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderSection(m.styles, "Fleet Registration"))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("  This will register the sensor with the fleet management system."))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderKeyValue(m.styles, "Sensor", sensor.ShortID()))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "Fleet Manager", "192.168.22.239"))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderMessage(m.styles, "info", "The sensor will be configured for P1 automation.", ""))
	b.WriteString("\n\n")

	b.WriteString(fmt.Sprintf("  Add sensor to fleet manager? %s / %s\n",
		m.styles.Success.Render("[y]es"),
		m.styles.Error.Render("[n]o")))

	return b.String()
}

func (m Model) renderAddingToFleet() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "ADDING TO FLEET", sensor.ShortID()))
	b.WriteString("\n\n")

	// Show elapsed time
	elapsed := time.Since(m.fleetStart).Round(time.Second)
	b.WriteString(ui.RenderKeyValue(m.styles, "Elapsed", formatElapsed(elapsed)))
	b.WriteString("\n")
	b.WriteString(ui.RenderKeyValue(m.styles, "IP Address", sensor.IP))
	b.WriteString("\n\n")

	// Progress indicator
	b.WriteString(ui.RenderSection(m.styles, "Progress"))
	b.WriteString("\n")

	if m.addingToFleet {
		b.WriteString(fmt.Sprintf("  %s Adding to fleet manager...\n", m.spinner.View()))
	}
	b.WriteString("\n")

	// Show logs
	b.WriteString(ui.RenderSection(m.styles, "Log"))
	b.WriteString("\n")
	for _, log := range m.fleetLogs {
		if strings.HasPrefix(log, "✓") {
			b.WriteString(m.styles.Success.Render("  " + log))
		} else if strings.HasPrefix(log, "✗") || strings.HasPrefix(log, "⚠") {
			b.WriteString(m.styles.Error.Render("  " + log))
		} else {
			b.WriteString(m.styles.Help.Render("  " + log))
		}
		b.WriteString("\n")
	}
	b.WriteString("\n")

	// Help text
	if m.addingToFleet {
		b.WriteString(m.styles.Help.Render("  Press ESC to return (operation will continue in background)"))
	} else {
		b.WriteString(m.styles.Help.Render("  Press any key to return to operations"))
	}
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderTrafficGenerator() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	// Header
	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "TRAFFIC GENERATOR", sensor.IP))
	b.WriteString("\n")

	// Breadcrumb
	b.WriteString(ui.RenderBreadcrumb(m.styles, "Home", "Sensors", sensor.ShortID(), "Traffic"))
	b.WriteString("\n\n")

	// Messages
	if m.errorMessage != "" {
		b.WriteString(ui.RenderMessage(m.styles, "error", m.errorMessage, ""))
		b.WriteString("\n")
	}
	if m.statusMessage != "" {
		b.WriteString(ui.RenderMessage(m.styles, "info", m.statusMessage, ""))
		b.WriteString("\n")
	}

	// Operations menu
	b.WriteString(ui.RenderSection(m.styles, "Traffic Operations"))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "1", "Configure sensor as traffic generator", "Install traffic generation tools", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "2", "Start traffic generation", "Begin sending traffic", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "3", "Stop traffic generation", "Halt all traffic generation", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "4", "View traffic statistics", "Show active processes", false))
	b.WriteString("\n")
	b.WriteString(ui.RenderMenuItem(m.styles, "5", "Back to operations", "Return to operations menu", false))
	b.WriteString("\n\n")

	b.WriteString(m.styles.Help.Render("  Select traffic operation [1-5]"))
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderTrafficStart() string {
	if m.selectedIdx >= len(m.sensors) {
		return "No sensor selected"
	}

	sensor := m.sensors[m.selectedIdx]
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(ui.RenderHeader(m.styles, "START TRAFFIC", sensor.IP))
	b.WriteString("\n\n")

	b.WriteString(ui.RenderSection(m.styles, "Traffic Configuration"))
	b.WriteString("\n")

	// Show inputs with current values
	ipLabel := "Target IP:"
	portLabel := "Target Port:"
	protoLabel := "Protocol:"
	ppsLabel := "Packets/sec:"
	durLabel := "Duration (0=continuous):"

	// Highlight current input
	switch m.trafficInputStep {
	case 0:
		b.WriteString(m.styles.Info.Render(fmt.Sprintf("  > %s %s_", ipLabel, m.trafficTargetIP)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", portLabel, m.trafficTargetPort)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", protoLabel, m.trafficProtocol)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", ppsLabel, m.trafficPPS)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", durLabel, m.trafficDuration)))
	case 1:
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", ipLabel, m.trafficTargetIP)))
		b.WriteString("\n")
		b.WriteString(m.styles.Info.Render(fmt.Sprintf("  > %s %s_", portLabel, m.trafficTargetPort)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", protoLabel, m.trafficProtocol)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", ppsLabel, m.trafficPPS)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", durLabel, m.trafficDuration)))
	case 2:
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", ipLabel, m.trafficTargetIP)))
		b.WriteString("\n")
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", portLabel, m.trafficTargetPort)))
		b.WriteString("\n")
		b.WriteString(m.styles.Info.Render(fmt.Sprintf("  > %s %s_ (udp/tcp/http/mixed)", protoLabel, m.trafficProtocol)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", ppsLabel, m.trafficPPS)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", durLabel, m.trafficDuration)))
	case 3:
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", ipLabel, m.trafficTargetIP)))
		b.WriteString("\n")
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", portLabel, m.trafficTargetPort)))
		b.WriteString("\n")
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", protoLabel, m.trafficProtocol)))
		b.WriteString("\n")
		b.WriteString(m.styles.Info.Render(fmt.Sprintf("  > %s %s_ (100-5000)", ppsLabel, m.trafficPPS)))
		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render(fmt.Sprintf("    %s %s", durLabel, m.trafficDuration)))
	case 4:
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", ipLabel, m.trafficTargetIP)))
		b.WriteString("\n")
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", portLabel, m.trafficTargetPort)))
		b.WriteString("\n")
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", protoLabel, m.trafficProtocol)))
		b.WriteString("\n")
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  ✓ %s %s", ppsLabel, m.trafficPPS)))
		b.WriteString("\n")
		b.WriteString(m.styles.Info.Render(fmt.Sprintf("  > %s %s_ (seconds, 0=continuous)", durLabel, m.trafficDuration)))
	}
	b.WriteString("\n\n")

	b.WriteString(m.styles.Help.Render("  Enter: Next field | ESC: Cancel"))
	b.WriteString("\n")

	return b.String()
}

func (m Model) helpContext() string {
	switch m.previousView {
	case ViewOperations:
		return "operations"
	default:
		return "main"
	}
}

// Commands
func tickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m Model) loadSensors() tea.Cmd {
	return func() tea.Msg {
		// Read sensor names from .sensors file
		sensorNames, err := readSensorsFile(m.config.SensorsFile)
		if err != nil {
			return sensorsLoadedMsg{err: err}
		}

		// Sort sensors by numeric ID (oldest first)
		sort.Slice(sensorNames, func(i, j int) bool {
			return extractNumericID(sensorNames[i]) < extractNumericID(sensorNames[j])
		})

		// Fetch each sensor from API
		var sensors []*models.Sensor
		var deletedSensors []string
		for _, name := range sensorNames {
			sensor, err := m.apiClient.FetchSensor(name)
			if err != nil {
				continue // Skip sensors that fail to load
			}
			if sensor.Deleted {
				// Track deleted sensors for cleanup
				deletedSensors = append(deletedSensors, name)
			} else {
				sensors = append(sensors, sensor)
			}
		}

		// Auto-cleanup: remove deleted sensors from .sensors file
		for _, name := range deletedSensors {
			removeSensorFromFile(m.config.SensorsFile, name)
		}

		return sensorsLoadedMsg{sensors: sensors}
	}
}

func (m Model) collectMetrics(sensorIdx int, ip string) tea.Cmd {
	return func() tea.Msg {
		metrics, err := m.sshClient.CollectMetrics(ip)
		return metricsLoadedMsg{
			sensorIdx: sensorIdx,
			metrics:   metrics,
			err:       err,
		}
	}
}

func (m Model) deleteSensor(sensorName string) tea.Cmd {
	return func() tea.Msg {
		err := m.apiClient.DeleteSensor(sensorName)
		if err == nil {
			// Also update .sensors file
			removeSensorFromFile(m.config.SensorsFile, sensorName)
		}
		return deleteResult{err: err}
	}
}

func (m Model) createSensor() tea.Cmd {
	return func() tea.Msg {
		sensorName, err := m.apiClient.CreateSensor()
		if err != nil {
			return deployStartedMsg{err: err}
		}

		// Add to .sensors file
		addSensorToFile(m.config.SensorsFile, sensorName)

		return deployStartedMsg{sensorName: sensorName}
	}
}

func (m Model) checkDeployStatus() tea.Cmd {
	return func() tea.Msg {
		if m.deployingSensorName == "" {
			return deployStatusMsg{err: fmt.Errorf("no sensor name")}
		}

		// First check API status
		sensor, err := m.apiClient.FetchSensor(m.deployingSensorName)
		if err != nil {
			return deployStatusMsg{err: err}
		}

		isRunning := sensor.Status == models.StatusRunning
		hasValidIP := sensor.IP != "" && sensor.IP != "null" && sensor.IP != "unknown"

		// If not running yet with valid IP, stay in phase 0
		if !isRunning || !hasValidIP {
			return deployStatusMsg{
				status:    string(sensor.Status),
				ip:        sensor.IP,
				isRunning: isRunning,
				phase:     0,
			}
		}

		// API says running with valid IP - now check SSH phases
		// Phase 1: Check SSH port
		if m.deployPhase < 1 {
			if m.sshClient.CheckSSHPort(sensor.IP) {
				return deployStatusMsg{
					status:      "running",
					ip:          sensor.IP,
					isRunning:   true,
					phase:       1,
					phaseStatus: "complete",
				}
			}
			return deployStatusMsg{
				status:      "running",
				ip:          sensor.IP,
				isRunning:   true,
				phase:       1,
				phaseStatus: "waiting",
			}
		}

		// Phase 2: Check SSH service
		if m.deployPhase < 2 {
			if m.sshClient.TestConnection(sensor.IP) {
				return deployStatusMsg{
					status:      "running",
					ip:          sensor.IP,
					isRunning:   true,
					phase:       2,
					phaseStatus: "complete",
				}
			}
			return deployStatusMsg{
				status:      "running",
				ip:          sensor.IP,
				isRunning:   true,
				phase:       2,
				phaseStatus: "waiting",
			}
		}

		// Phase 3: Check seeding status
		seeded, seededValue, _ := m.sshClient.CheckSeeded(sensor.IP)
		if seeded {
			return deployStatusMsg{
				status:      "running",
				ip:          sensor.IP,
				isRunning:   true,
				phase:       3,
				phaseStatus: "complete",
				seededValue: seededValue,
			}
		}
		return deployStatusMsg{
			status:      "running",
			ip:          sensor.IP,
			isRunning:   true,
			phase:       3,
			phaseStatus: "waiting",
			seededValue: seededValue,
		}
	}
}

// loadUpgradeInfo fetches current version and available updates from the sensor
func (m Model) loadUpgradeInfo(ip string) tea.Cmd {
	return func() tea.Msg {
		// Get admin password from sensor config
		adminPassword, err := m.sshClient.GetAdminPassword(ip)
		if err != nil {
			return upgradeInfoMsg{err: fmt.Errorf("failed to get admin password: %v", err)}
		}

		// Get current version
		currentVersion, err := m.sshClient.GetSensorVersion(ip, adminPassword)
		if err != nil {
			currentVersion = "unknown"
		}

		// Get release channel
		releaseChannel, err := m.sshClient.GetReleaseChannel(ip)
		if err != nil {
			releaseChannel = "testing"
		}

		// Get available updates
		availableVersions, _ := m.sshClient.GetAvailableUpdates(ip, adminPassword)

		return upgradeInfoMsg{
			currentVersion:    currentVersion,
			availableVersions: availableVersions,
			releaseChannel:    releaseChannel,
			adminPassword:     adminPassword,
		}
	}
}

// runUpgrade executes the upgrade command on the sensor
func (m Model) runUpgrade(ip string) tea.Cmd {
	return func() tea.Msg {
		var err error
		if m.upgradeOption == 1 {
			// Upgrade to latest using corelight-client updates apply
			err = m.sshClient.RunUpgradeLatest(ip, m.upgradeAdminPassword)
		} else {
			// Upgrade to specific version using broala-update-repository
			// Map channel to repository
			repo := "brolin-testing"
			switch m.upgradeReleaseChannel {
			case "dev", "development":
				repo = "brolin-development"
			case "release", "stable":
				repo = "brolin-release"
			}
			err = m.sshClient.RunUpgradeSpecific(ip, repo, m.upgradeTargetVersion)
		}

		return upgradeStartedMsg{err: err}
	}
}

// checkUpgradeProgress monitors the upgrade status via SSH
func (m Model) checkUpgradeProgress(ip string) tea.Cmd {
	return func() tea.Msg {
		// Check if SSH is available (sensor might be rebooting)
		sshAvailable := m.sshClient.TestConnection(ip)
		if !sshAvailable {
			return upgradeProgressMsg{sshAvailable: false}
		}

		// Check if upgrade processes are running
		processRunning := m.sshClient.IsUpgradeProcessRunning(ip)
		if processRunning {
			return upgradeProgressMsg{sshAvailable: true, processRunning: true}
		}

		// Try to get the new version
		newVersion, err := m.sshClient.GetSensorVersion(ip, m.upgradeAdminPassword)
		if err != nil {
			return upgradeProgressMsg{sshAvailable: true, processRunning: false, err: err}
		}

		return upgradeProgressMsg{
			sshAvailable:   true,
			processRunning: false,
			newVersion:     newVersion,
		}
	}
}

// runEnableFeatures runs the enable_sensor_features.sh script via SSH
func (m Model) runEnableFeatures(ip string) tea.Cmd {
	return func() tea.Msg {
		output, err := m.sshClient.EnableFeatures(ip)
		return enableFeaturesResultMsg{output: output, err: err}
	}
}

// runAddToFleet runs the prepare_p1_automation.sh script
func (m Model) runAddToFleet(ip string) tea.Cmd {
	return func() tea.Msg {
		output, err := m.sshClient.AddToFleetManager(ip)
		return fleetResultMsg{output: output, err: err}
	}
}

// trafficConfigResultMsg is returned after configuring traffic generator
type trafficConfigResultMsg struct {
	err error
}

// runConfigureTrafficGenerator configures the sensor as a traffic generator
func (m Model) runConfigureTrafficGenerator(ip string) tea.Cmd {
	return func() tea.Msg {
		err := m.sshClient.ConfigureTrafficGenerator(ip)
		return trafficConfigResultMsg{err: err}
	}
}

func (m Model) sshCommand(ip string) *exec.Cmd {
	args := []string{
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		fmt.Sprintf("%s@%s", m.config.SSHUsername, ip),
	}
	return exec.Command("ssh", args...)
}

func (m *Model) countSensors() {
	m.runningCount = 0
	m.errorCount = 0
	for _, sensor := range m.sensors {
		switch sensor.Status {
		case models.StatusRunning:
			m.runningCount++
		case models.StatusError:
			m.errorCount++
		}
	}
}

// File operations
func readSensorsFile(path string) ([]string, error) {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return []string{}, nil
		}
		return nil, err
	}
	defer file.Close()

	var sensors []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			sensors = append(sensors, line)
		}
	}
	return sensors, scanner.Err()
}

func removeSensorFromFile(path, sensorName string) error {
	sensors, err := readSensorsFile(path)
	if err != nil {
		return err
	}

	var filtered []string
	for _, s := range sensors {
		if s != sensorName {
			filtered = append(filtered, s)
		}
	}

	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	for _, s := range filtered {
		fmt.Fprintln(file, s)
	}
	return nil
}

func addSensorToFile(path, sensorName string) error {
	// Check if already exists
	sensors, _ := readSensorsFile(path)
	for _, s := range sensors {
		if s == sensorName {
			return nil // Already exists
		}
	}

	// Append to file
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = fmt.Fprintln(file, sensorName)
	return err
}

func shortenSensorName(name string) string {
	parts := strings.Split(name, "-")
	if len(parts) > 0 {
		lastPart := parts[len(parts)-1]
		if len(lastPart) > 8 {
			return lastPart[:8]
		}
		return lastPart
	}
	return name
}

func extractNumericID(sensorName string) int64 {
	parts := strings.Split(sensorName, "-")
	if len(parts) > 0 {
		if id, err := strconv.ParseInt(parts[len(parts)-1], 10, 64); err == nil {
			return id
		}
	}
	return 0
}

// formatElapsed formats a duration like the bash script does: [30s], [1m30s], etc.
func formatElapsed(d time.Duration) string {
	secs := int(d.Seconds())
	if secs < 60 {
		return fmt.Sprintf("%ds", secs)
	} else if secs < 3600 {
		mins := secs / 60
		remSecs := secs % 60
		if remSecs == 0 {
			return fmt.Sprintf("%dm", mins)
		}
		return fmt.Sprintf("%dm%ds", mins, remSecs)
	}
	hours := secs / 3600
	mins := (secs % 3600) / 60
	return fmt.Sprintf("%dh%dm", hours, mins)
}

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("Failed to load config: %v\n", err)
		os.Exit(1)
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		fmt.Printf("Configuration error: %v\n", err)
		fmt.Println("")
		fmt.Println("Please configure your environment:")
		fmt.Println("  Copy env.example to .env and fill in your credentials.")
		fmt.Println("")
		fmt.Println("Required variables:")
		fmt.Println("  EC2_SENSOR_BASE_URL - API endpoint URL")
		fmt.Println("  EC2_SENSOR_API_KEY  - API authentication key")
		os.Exit(1)
	}

	// Initialize model
	m := initialModel(cfg)

	// Create and run program
	p := tea.NewProgram(
		m,
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}
