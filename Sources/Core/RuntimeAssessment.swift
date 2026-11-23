import Foundation

struct RuntimeFinding: Identifiable {
    enum Severity { case blocker, warning, info }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
}

/// Derives feasibility findings from inspected facts. Nothing here is hard-coded per app:
/// the verdict follows from file type, signing team, entitlements and encryption flags.
enum RuntimeAssessment {
    static func ownTeamID() -> String? {
        guard let executable = Bundle.main.executableURL, let own = try? MachOInspector.inspect(url: executable) else { return nil }
        return own.teamID
    }

    static func evaluate(_ report: MachOReport, ownTeam: String? = ownTeamID()) -> [RuntimeFinding] {
        var findings: [RuntimeFinding] = []

        if report.isExecutable {
            findings.append(RuntimeFinding(
                severity: .blocker,
                title: "It's a program, not a library",
                detail: "This binary is a Mach-O executable. dyld only loads dylibs and bundles into another process, so dlopen rejects it however it's signed."))
        }

        if report.hasCodeSignature, let team = report.teamID {
            if team != ownTeam {
                findings.append(RuntimeFinding(
                    severity: .blocker,
                    title: "Signed by a different team (\(team))",
                    detail: "iOS only maps code signed by the app's own team. AETHER's team is \(ownTeam ?? "not available in this build"). Replacing the signature would be a code-signing bypass, which AETHER doesn't do."))
            }
        } else if !report.hasCodeSignature {
            findings.append(RuntimeFinding(
                severity: .blocker,
                title: "No code signature",
                detail: "iOS refuses to run or load unsigned code on a stock device."))
        }

        let identity = report.entitlements.keys.filter {
            $0 == "application-identifier" || $0 == "keychain-access-groups" || $0 == "aps-environment"
        }
        if !identity.isEmpty {
            findings.append(RuntimeFinding(
                severity: .blocker,
                title: "Identity-bound entitlements",
                detail: "\(identity.sorted().joined(separator: ", ")) belong to the original developer's provisioning. AETHER can't hold them, so sign-in, push and Keychain data tied to them wouldn't work."))
        }

        if let cryptID = report.cryptID {
            if cryptID == 0 {
                findings.append(RuntimeFinding(
                    severity: .warning,
                    title: "FairPlay layer already removed",
                    detail: "cryptid is 0, so this copy isn't in its App Store form. AETHER doesn't build on binaries with the encryption removed."))
            } else {
                findings.append(RuntimeFinding(
                    severity: .info,
                    title: "FairPlay encrypted",
                    detail: "Only the system can decrypt this for the Apple ID that owns it, and only when launched as its own app."))
            }
        }

        findings.append(RuntimeFinding(
            severity: .blocker,
            title: "No way to host or overlay another app",
            detail: "iOS has no API to embed another app's UI or draw above it, and UIApplication is one per process. A floating AETHER button can't sit over real Minecraft gameplay."))
        findings.append(RuntimeFinding(
            severity: .blocker,
            title: "No public camera integration point",
            detail: "The camera lives in the game's private state. Changing it from outside would need memory patching or hooking, which AETHER doesn't do."))
        return findings
    }

    static func verdict(_ findings: [RuntimeFinding]) -> String {
        findings.contains { $0.severity == .blocker }
            ? "Cannot run inside AETHER on stock iOS"
            : "No blockers found by static checks"
    }
}
