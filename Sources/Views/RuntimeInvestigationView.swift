import SwiftUI

struct RuntimeInvestigationView: View {
    @State private var importing = false
    @State private var working = false
    @State private var report: MachOReport?
    @State private var findings: [RuntimeFinding] = []
    @State private var errorMessage: String?

    var body: some View {
        Screen {
            Text("Runtime investigation")
                .font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Pick a binary in Files, for example the minecraftpe executable from an app bundle you own. AETHER reads its headers and signature and lists what stops it from running inside AETHER. It never loads, runs or modifies the file.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)

            Button { Haptics.tap(); importing = true } label: {
                Label(working ? "Reading..." : "Choose a binary", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(working)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Theme.warning)
            }

            if let report {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RuntimeAssessment.verdict(findings))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(findings.contains { $0.severity == .blocker } ? Theme.warning : Theme.accent)
                    Text(report.fileName).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                .glassCard()

                VStack(spacing: 10) {
                    InfoRow(label: "Architecture", value: report.architecture)
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "File type", value: report.fileType)
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Platform", value: [report.platform, report.minOS.map { "iOS \($0)+" }].compactMap { $0 }.joined(separator: ", ").nilIfEmpty ?? "Unknown")
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Code signature", value: report.hasCodeSignature ? "Present" : "Absent")
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Team ID", value: report.teamID ?? "None")
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "FairPlay cryptid", value: report.cryptID.map(String.init) ?? "No encryption info")
                }
                .glassCard()

                ForEach(findings) { finding in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(finding.title, systemImage: symbol(finding.severity))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(color(finding.severity))
                        Text(finding.detail).font(.footnote).foregroundStyle(.white.opacity(0.84))
                    }
                    .glassCard(radius: 18, padding: 14)
                }

                DisclosureGroup("Entitlements (\(report.entitlements.count))") {
                    detailLines(report.entitlements.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" })
                }
                .tint(Theme.accent).foregroundStyle(.white).glassCard(radius: 18, padding: 14)

                DisclosureGroup("Linked libraries (\(report.libraries.count))") {
                    detailLines(report.libraries.map { "\($0.kind)  \($0.name)" })
                }
                .tint(Theme.accent).foregroundStyle(.white).glassCard(radius: 18, padding: 14)

                ShareLink(item: exportText(report)) { Label("Share report", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            Text("AETHER's own signing team: \(RuntimeAssessment.ownTeamID() ?? "none (unsigned or ad-hoc build)")")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .navigationTitle("Investigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { analyze(url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func analyze(_ url: URL) {
        working = true
        errorMessage = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<MachOReport, Error> in
                do { return .success(try MachOInspector.inspect(url: url)) } catch { return .failure(error) }
            }.value
            switch outcome {
            case .success(let result):
                report = result
                findings = RuntimeAssessment.evaluate(result)
            case .failure(let error):
                report = nil
                findings = []
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func exportText(_ report: MachOReport) -> String {
        var lines = [RuntimeAssessment.verdict(findings), "", report.text, "", "Findings:"]
        for finding in findings { lines.append("- \(finding.title): \(finding.detail)") }
        return lines.joined(separator: "\n")
    }

    private func detailLines(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func symbol(_ severity: RuntimeFinding.Severity) -> String {
        switch severity {
        case .blocker: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: RuntimeFinding.Severity) -> Color {
        switch severity {
        case .blocker: return Color(red: 0.95, green: 0.45, blue: 0.40)
        case .warning: return Theme.warning
        case .info: return Theme.accent
        }
    }
}
