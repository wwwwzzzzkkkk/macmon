import Testing
@testable import ChipBar

@MainActor struct DashboardOpeningStateTests {
    @Test func normalReopenResetsEveryEphemeralControl() {
        let state = DashboardState()
        state.chartMetric = .cpu
        state.showSettings = true
        state.showApplications = true
        state.applicationsExpansion = 1
        state.showSSDDetails = true
        state.ssdExpansion = 1
        state.showSystemDetails = true
        state.ssdDetailsHeight = 200
        state.applicationMetric = .memory

        state.resetForOpening(arguments: ["ChipBar"])

        #expect(state.chartMetric == .total)
        #expect(!state.showSettings)
        #expect(!state.showApplications)
        #expect(state.applicationsExpansion == 0)
        #expect(!state.showSSDDetails)
        #expect(state.ssdExpansion == 0)
        #expect(!state.showSystemDetails)
        #expect(state.ssdDetailsHeight == 0)
        #expect(state.applicationMetric == .cpu)
    }

    @Test func screenshotsKeepTheirExplicitQAOverrides() {
        let state = DashboardState()
        state.resetForOpening(arguments: ["ChipBar", "--apps", "--ssd-details", "--apps-gpu"])
        #expect(state.showApplications)
        #expect(state.applicationsExpansion == 1)
        #expect(state.showSSDDetails)
        #expect(state.ssdExpansion == 1)
        #expect(state.showSystemDetails)
        #expect(state.applicationMetric == .gpu)

        state.resetForOpening(arguments: ["ChipBar", "--system-details", "--apps-ane"])
        #expect(!state.showApplications)
        #expect(!state.showSSDDetails)
        #expect(state.showSystemDetails)
        #expect(state.applicationMetric == .ane)
    }
}
