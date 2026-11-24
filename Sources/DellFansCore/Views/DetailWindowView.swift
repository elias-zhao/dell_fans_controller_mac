import SwiftUI

public struct DetailWindowView: View {
    private enum SidebarItem: String, CaseIterable, Identifiable {
        case sensors = "传感器"
        case settings = "连接设置"
        case about = "关于"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .sensors:
                return "thermometer.medium"
            case .settings:
                return "gearshape"
            case .about:
                return "info.circle"
            }
        }
    }

    @ObservedObject private var appState: AppState
    @State private var selection: SidebarItem?

    public init(appState: AppState) {
        self.appState = appState
        _selection = State(initialValue: appState.config.isConfigured ? .sensors : .settings)
    }

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 220)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(currentItem.rawValue)
    }

    private var currentItem: SidebarItem {
        selection ?? .sensors
    }

    @ViewBuilder
    private var detailContent: some View {
        switch currentItem {
        case .sensors:
            SensorTableView(appState: appState)
        case .settings:
            ConnectionSettingsView(appState: appState)
        case .about:
            AboutView(appState: appState)
        }
    }
}
