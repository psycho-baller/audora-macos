// SignInView.swift
// Authentication view for Clerk sign-in

import SwiftUI
import AuthenticationServices
import Clerk

struct SignInView: View {
    @ObservedObject private var convexService = ConvexService.shared

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSigningIn: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("Welcome to Audora")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign in to sync your meetings and notes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Sign in form
            VStack(spacing: 20) {
                // Sign in with Apple button
                SignInWithAppleButton(.signIn) { request in
                    print("🍎 [Apple Sign-In] Configuring request...")
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task {
                        await handleAppleSignIn(result)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(10)

                // Sign in with Google button
                Button(action: signInWithGoogle) {
                    HStack(spacing: 12) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 20))
                        Text("Sign in with Google")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)

                // Divider
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }
                .padding(.vertical, 10)

                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .textContentType(.emailAddress)
                }

                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .textContentType(.password)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Sign in button
                Button(action: signIn) {
                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 400)

            Spacer()

            // Footer
            VStack(spacing: 8) {
                Text("By signing in, you agree to our")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://audora.psycho-baller.com/terms")!)
                    Text("and")
                        .foregroundColor(.secondary)
                    Link("Privacy Policy", destination: URL(string: "https://audora.psycho-baller.com/privacy")!)
                }
                .font(.caption)
            }
            .padding(.bottom, 30)
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            print("📱 [SignInView] View appeared")
            logClerkState()
        }
    }

    private func logClerkState() {
        print("🔐 [Clerk State] Checking Clerk configuration...")
        print("   - Clerk.shared.session: \(Clerk.shared.session != nil ? "exists" : "nil")")
        print("   - Clerk.shared.user: \(Clerk.shared.user != nil ? "exists (\(Clerk.shared.user?.id ?? "no id"))" : "nil")")
        print("   - Clerk.shared.client: \(Clerk.shared.client != nil ? "exists" : "nil")")
        if let client = Clerk.shared.client {
            print("   - Client sessions count: \(client.sessions.count)")
            print("   - Client lastActiveSessionId: \(client.lastActiveSessionId ?? "nil")")
            for session in client.sessions {
                print("   - Session: \(session.id), status: \(session.status)")
            }
        }
    }

    private func signIn() {
        print("📧 [Email Sign-In] Starting with email: \(email)")
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                print("📧 [Email Sign-In] Calling SignIn.create...")
                let signIn = try await SignIn.create(strategy: .identifier(email, password: password))
                print("📧 [Email Sign-In] ✅ Success! SignIn ID: \(signIn.id)")
                
                // Set this session as active
                if let sessionId = signIn.createdSessionId {
                    print("📧 [Email Sign-In] Setting session active: \(sessionId)")
                    try await Clerk.shared.setActive(sessionId: sessionId)
                }
                
                logClerkState()
                ConvexService.shared.onSignInComplete()
            } catch {
                let fullError = formatDetailedError(error)
                print("📧 [Email Sign-In] ❌ Error: \(fullError)")
                errorMessage = fullError
            }
            isSigningIn = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        print("🍎 [Apple Sign-In] Handling result...")

        switch result {
        case .success(let authorization):
            print("🍎 [Apple Sign-In] ASAuthorization success")
            print("   - Credential type: \(type(of: authorization.credential))")

            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                print("   - User ID: \(appleIDCredential.user)")
                print("   - Email: \(appleIDCredential.email ?? "nil")")
                print("   - Full Name: \(appleIDCredential.fullName?.givenName ?? "nil") \(appleIDCredential.fullName?.familyName ?? "nil")")
            }

            do {
                print("🍎 [Apple Sign-In] Calling Clerk SignIn.create with OAuth...")
                let signIn = try await SignIn.create(strategy: .oauth(provider: .apple))
                print("🍎 [Apple Sign-In] ✅ Success! SignIn ID: \(signIn.id)")
                logClerkState()
                ConvexService.shared.onSignInComplete()
            } catch {
                let fullError = formatDetailedError(error)
                print("🍎 [Apple Sign-In] ❌ Clerk OAuth error: \(fullError)")
                errorMessage = fullError
            }

        case .failure(let error):
            let fullError = formatDetailedError(error)
            print("🍎 [Apple Sign-In] ❌ ASAuthorization failed: \(fullError)")
            errorMessage = fullError
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Common cancellation error codes:
        // - NSURLErrorCancelled (-999)
        // - ASWebAuthenticationSessionErrorCanceled (1)
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled ||
               nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1 ||
               nsError.localizedDescription.lowercased().contains("cancel")
    }

    private func signInWithGoogle() {
        print("🔵 [Google Sign-In] Starting...")
        isSigningIn = true
        errorMessage = nil
        logClerkState()

        Task {
            do {
                print("🔵 [Google Sign-In] Calling authenticateWithRedirect...")
                try await SignIn.create(strategy: .oauth(provider: .google))
                    .authenticateWithRedirect()
                
                print("🔵 [Google Sign-In] ✅ Authentication completed!")
                
                // Refresh client to get the new session
                _ = try await Client.get()
                logClerkState()
                
                if Clerk.shared.session != nil {
                    print("🔵 [Google Sign-In] Session established!")
                    ConvexService.shared.onSignInComplete()
                } else {
                    print("🔵 [Google Sign-In] ⚠️ No session after authentication")
                    errorMessage = "Authentication completed but no session was created"
                }
            } catch {
                if isCancellationError(error) {
                    print("🔵 [Google Sign-In] ℹ️ User cancelled sign-in")
                } else {
                    let fullError = formatDetailedError(error)
                    print("🔵 [Google Sign-In] ❌ Error: \(fullError)")
                    errorMessage = fullError
                }
            }
            isSigningIn = false
        }
    }

    private func formatDetailedError(_ error: Error) -> String {
        let nsError = error as NSError
        var details = """
        Error: \(error.localizedDescription)
        Domain: \(nsError.domain)
        Code: \(nsError.code)
        """

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            details += "\nUnderlying: \(underlyingError.localizedDescription)"
        }

        if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            details += "\nReason: \(failureReason)"
        }

        if let recoverySuggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String {
            details += "\nSuggestion: \(recoverySuggestion)"
        }

        // Print full userInfo for debugging
        print("   Full userInfo: \(nsError.userInfo)")

        return details
    }
}

#Preview {
    SignInView()
}
