import SwiftUI

struct ActivityMonitorView: View {
    @StateObject private var viewModel = ActivityMonitorViewModel()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabSelector
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vortexMaterial)
        .onAppear {
            viewModel.startTracking()
        }
    }

    private var headerView: some View {
        HStack {
            Text("Activity")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.vortexText)

            Spacer()

            Button(action: { viewModel.refreshActivities() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.vortexTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.vortexMaterialSecondary)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton("Apps", index: 0)
            tabButton("Browsers", index: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            Text(title)
                .font(.system(size: 13, weight: selectedTab == index ? .medium : .regular))
                .foregroundColor(selectedTab == index ? .vortexAccent : .vortexTextSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .background(selectedTab == index ? Color.vortexAccent.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var contentView: some View {
        if selectedTab == 0 {
            appsListView
        } else {
            browsersListView
        }
    }

    private var appsListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if viewModel.activities.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.activities, id: \.id) { activity in
                        ActivityRowView(activity: activity) {
                            viewModel.activateActivity(activity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var browsersListView: some View {
        VStack(spacing: 0) {
            browserPicker
            browserTabsList
        }
    }

    private var browserPicker: some View {
        HStack {
            Picker("Browser", selection: $viewModel.selectedBrowser) {
                Text("Safari").tag("Safari")
                Text("Chrome").tag("Chrome")
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedBrowser) { _, _ in
                viewModel.refreshBrowserTabs()
            }

            Button(action: { viewModel.refreshBrowserTabs() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var browserTabsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if viewModel.isLoadingBrowser {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if viewModel.browserTabs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: viewModel.selectedBrowser == "Safari" ? "safari" : "globe")
                            .font(.system(size: 30))
                            .foregroundColor(.vortexTextSecondary.opacity(0.5))
                        Text("No tabs found")
                            .font(.system(size: 13))
                            .foregroundColor(.vortexTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ForEach(viewModel.browserTabs) { tab in
                        BrowserTabRow(tab: tab) {
                            viewModel.activateWebPage(tab)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.ghost")
                .font(.system(size: 40))
                .foregroundColor(.vortexTextSecondary.opacity(0.5))

            Text("No activity yet")
                .font(.system(size: 15))
                .foregroundColor(.vortexTextSecondary)

            Text("Start using apps to see them here")
                .font(.system(size: 13))
                .foregroundColor(.vortexTextSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct ActivityRowView: View {
    let activity: ActivityItem
    let onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            if let iconData = activity.appIcon, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.vortexTextSecondary)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.vortexText)

                Text(activity.timeSinceActive)
                    .font(.system(size: 11))
                    .foregroundColor(.vortexTextSecondary)
            }

            Spacer()

            if activity.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            if isHovered {
                Button(action: onActivate) {
                    Text("Activate")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.vortexAccent)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.vortexMaterialSecondary : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct BrowserTabRow: View {
    let tab: BrowserActivityAdapter.BrowserTab
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundColor(.vortexTextSecondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(size: 12))
                    .foregroundColor(.vortexText)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.system(size: 10))
                    .foregroundColor(.vortexTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.vortexMaterialSecondary.opacity(0.5))
        .cornerRadius(6)
        .onTapGesture {
            onActivate()
        }
    }
}