import SwiftUI
import UIKit

struct SettingsScreen: View {
    @AppStorage("proofcam.cameraGrid") private var cameraGrid = false
    @AppStorage("proofcam.shutterHaptics") private var shutterHaptics = true
    @AppStorage("proofcam.saveToPhotos") private var saveToPhotos = true
    @State private var showingGuide = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ZStack { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ProofCamTheme.ink); ProofWorkshopIllustration(compact: true).padding(7) }
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The proof workshop").font(.system(.title3, design: .serif).weight(.bold))
                            Text("Proof that travels with the photo.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Camera") {
                    Toggle(isOn: $cameraGrid) { Label("Camera grid", systemImage: "grid") }
                    Toggle(isOn: $shutterHaptics) { Label("Shutter haptics", systemImage: "waveform") }
                }
                Section {
                    Toggle(isOn: $saveToPhotos) { Label("Save to Photos", systemImage: "photo.on.rectangle") }
                } header: { Text("Saving") } footer: {
                    Text("Signed copies always stay in ProofCam. When enabled, photos are also added to your camera roll. You can save them manually from the photo viewer at any time.")
                }
                Section {
                    HStack {
                        Text("Photo signing")
                        Spacer()
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(ProofCamTheme.success)
                        Text("Always on").foregroundStyle(ProofCamTheme.success)
                    }.frame(height: 28)
                } header: { Text("Signatures") } footer: {
                    Text("Every completed JPEG carries its signed SHA-256 proof inside the file. The private key stays protected by your iPhone’s Secure Enclave. This detects changes; it does not decide whether a scene is truthful.")
                }
                Section("Help & privacy") {
                    Button { showingGuide = true } label: { Label("How ProofCam works", systemImage: "book") }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Label("Camera & Photos permissions", systemImage: "hand.raised") }
                    Label("No automatic photo uploads", systemImage: "lock").foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")
                    Text("Built for people documenting the world: journalists, researchers, field teams, and anyone who wants a verifiable record of a saved photo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden).background(ProofCamTheme.canvas)
                .navigationTitle("Settings").tint(ProofCamTheme.accent)
        }
        .sheet(isPresented: $showingGuide) { IntroductionScreen(completionTitle: "Done") { showingGuide = false } }
    }
}

struct IntroductionScreen: View {
    var completionTitle = "Open camera"
    let completed: () -> Void
    @State private var page = 0
    private let pages: [(symbol: String, eyebrow: String, title: String, body: String, note: String)] = [
        ("camera", "01  CAPTURE", "Take the photo.",
         "ProofCam uses a real camera capture, then prepares one durable JPEG on your iPhone.",
         "Nothing is uploaded. No account is required."),
        ("lock.shield", "02  PROTECT", "The proof stays inside.",
         "A Secure Enclave key signs the image’s SHA-256 proof. That signed record is embedded directly in the JPEG.",
         "Share one photo—not a photo plus a fragile sidecar file."),
        ("checkmark.circle", "03  VERIFY", "Check for change.",
         "Anyone with the original can open Verify and check whether its embedded proof still matches.",
         "ProofCam confirms integrity. It does not claim that a photographed scene is truthful.")
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProofCamMark()
                Spacer()
                Text("\(page + 1) / \(pages.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.top, 24)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ProofCamTheme.paper)
                                ProofWorkshopIllustration().padding(12)
                            }.frame(height: 250).overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ProofCamTheme.line) }
                            WorkshopEyebrow(text: pages[index].eyebrow)
                            Text(pages[index].title).font(.system(.largeTitle, design: .serif).weight(.bold)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                            Text(pages[index].body).font(.body).foregroundStyle(ProofCamTheme.ink.opacity(0.84)).fixedSize(horizontal: false, vertical: true)
                            Text(pages[index].note).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: 500).padding(.horizontal, 28).padding(.bottom, 24)
                    }.tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 20) {
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule().fill(page == index ? ProofCamTheme.blue : Color.black.opacity(0.12)).frame(width: page == index ? 22 : 6, height: 6)
                    }
                }.accessibilityLabel("Introduction page \(page + 1) of \(pages.count)")
                Button {
                    if page == pages.count - 1 { completed() }
                    else { withAnimation { page += 1 } }
                } label: {
                    HStack { Spacer(); Text(page == pages.count - 1 ? completionTitle : "Continue").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }
                        .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 56)
                        .background(ProofCamTheme.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
                Text("No account. Photos are processed on your device.").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.bottom, 24)
        }.background(ProofCamTheme.canvas).foregroundStyle(ProofCamTheme.ink)
    }
}
