import SwiftUI

/// "Connect Slack" setup window: create the per-user Slack app from a manifest,
/// paste the two tokens, validate them live, store them in the Keychain, and
/// start the listener. SwiftUI adaptation of the former `slackhtml setup` CLI.
struct SlackSetupView: View {
    let controller: SlackController
    @Environment(\.dismiss) private var dismiss

    @State private var appToken = ""
    @State private var userToken = ""
    @State private var phase: Phase = .idle
    @State private var message = ""

    private enum Phase { case idle, validating, success, failure }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Slack").font(.title2).bold()
                Text("React 👀 on a .html or .md in Slack to open it in mdLens.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Create your Slack app from the manifest, then pick the workspace.")
                    Button("Create Slack App (manifest)…") { ManifestService.openCreateApp() }
                    step(2, "Basic Information → App-Level Tokens → Generate (scope connections:write) → copy the xapp-… token.")
                    step(3, "Install App → Install to Workspace → copy the User OAuth Token (xoxp-…).")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("App-level token").font(.caption).foregroundStyle(.secondary)
                SecureField("xapp-…", text: $appToken)
                    .textFieldStyle(.roundedBorder)
                Text("User OAuth token").font(.caption).foregroundStyle(.secondary)
                SecureField("xoxp-…", text: $userToken)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Button("Connect") { Task { await connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(phase == .validating || !inputsLookValid)
                if phase == .validating { ProgressView().controlSize(.small) }
                statusLabel
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").bold()
            Text(text)
        }
        .font(.callout)
    }

    private var inputsLookValid: Bool {
        appToken.hasPrefix("xapp-") && appToken.count > 20 &&
        userToken.hasPrefix("xoxp-") && userToken.count > 20
    }

    @ViewBuilder private var statusLabel: some View {
        switch phase {
        case .success:
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure:
            Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .validating:
            Text(message).foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    /// Validate both tokens live, then persist and start the listener.
    private func connect() async {
        phase = .validating
        message = "Validating…"
        let api = SlackAPI(webToken: userToken, appToken: appToken)
        do {
            let uid = try await api.authTestUserID()   // user token ok
            _ = try await api.openConnection()         // app token / Socket Mode reachable
            guard Keychain.set(appToken, account: Keychain.appTokenAccount),
                  Keychain.set(userToken, account: Keychain.userTokenAccount) else {
                phase = .failure
                message = "Couldn't save to Keychain"
                return
            }
            controller.start(with: SlackConfig(appToken: appToken, webToken: userToken, triggerEmoji: "eyes"))
            phase = .success
            message = "Connected (\(uid))"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        } catch {
            phase = .failure
            message = "Validation failed: \(error)"
        }
    }
}
