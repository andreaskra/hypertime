import SwiftUI
import HypertimeCore

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Tracking") {
                Picker("Check-in every", selection: $viewModel.checkInIntervalMinutes) {
                    ForEach(Settings.checkInIntervalChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : "\(minutes) min").tag(minutes)
                    }
                }
                Toggle("Pause while asleep or locked", isOn: $viewModel.pauseOnSleepAndLock)
                Picker("Morning starts at", selection: $viewModel.morningHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                Picker("Hide passive popup after", selection: $viewModel.passiveAutoHide) {
                    Text("Never").tag(0)
                    ForEach([10, 20, 30, 60], id: \.self) { Text("\($0) s").tag($0) }
                }
            }

            Section("Appearance") {
                Picker("Show times as", selection: $viewModel.timeDisplayStyle) {
                    Text("1:30:15").tag(TimeStyle.clock)
                    Text("1:30").tag(TimeStyle.clockNoSeconds)
                    Text("1h 30m").tag(TimeStyle.units)
                    Text("1.50").tag(TimeStyle.decimalHours)
                }
                Toggle("Show elapsed time in the menu bar", isOn: $viewModel.showElapsedInMenuBar)
                Picker("Week starts on", selection: $viewModel.weekStart) {
                    Text("Monday").tag(Weekday.monday)
                    Text("Sunday").tag(Weekday.sunday)
                }
            }

            Section("System") {
                Toggle("Show in Dock and Cmd+Tab", isOn: $viewModel.showInDockAndCmdTab)
                Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                if viewModel.loginItemNeedsApproval {
                    Text("Approve Hypertime in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !viewModel.isInApplicationsFolder {
                    Text("Move Hypertime to /Applications for a reliable login item.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Export defaults") {
                Toggle("Use semicolon as CSV delimiter", isOn: $viewModel.csvDelimiterIsSemicolon)
                Picker("CSV cell format", selection: $viewModel.csvCellStyle) {
                    Text("1:30:15").tag(TimeStyle.clock)
                    Text("1:30").tag(TimeStyle.clockNoSeconds)
                    Text("1.50 (decimal hours)").tag(TimeStyle.decimalHours)
                }
                Toggle("Include totals row and column", isOn: $viewModel.csvIncludeTotals)
            }

            Section {
                Text(viewModel.databasePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Database")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}
