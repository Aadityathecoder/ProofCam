import SwiftUI
import UIKit

struct SettingsScreen: View {
    @AppStorage("proofcam.cameraGrid") private var cameraGrid = false
    @AppStorage("proofcam.shutterHaptics") private var shutterHaptics = true
    @AppStorage("proofcam.saveToPhotos") private var saveToPhotos = true
    @State private var showingGuide = false
    @State private var showingLab = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        RegistrationMark().stroke(ProofCamTheme.onPrimary, lineWidth: 1.6)
                            .frame(width: 26, height: 26).frame(width: 52, height: 52)
                            .background(ProofCamTheme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ProofCam").font(ProofCamType.display(20, relativeTo: .title3))
                            Text("Capture and image integrity").font(.subheadline).foregroundStyle(ProofCamTheme.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("Camera") {
                    Toggle("Camera grid", isOn: $cameraGrid)
                    Toggle("Shutter haptics", isOn: $shutterHaptics)
                }
                Section {
                    Toggle("Save to Photos", isOn: $saveToPhotos)
                } header: { Text("Saving") } footer: {
                    Text("Signed copies always stay in ProofCam. When enabled, photos are also added to your camera roll. You can save them manually from the photo viewer at any time.")
                }
                Section {
                    HStack {
                        Text("Photo signing")
                        Spacer()
                        Label("Always on", systemImage: "checkmark.circle").foregroundStyle(ProofCamTheme.success)
                    }.accessibilityElement(children: .combine)
                } header: { Text("Signatures") } footer: {
                    Text("Every completed JPEG carries its signed SHA-256 proof inside the file. The private key stays protected by your iPhone’s Secure Enclave. This detects changes; it does not decide whether a scene is truthful.")
                }
                Section("Help & privacy") {
                    Button("How ProofCam works") { showingGuide = true }
                    Button("Camera & Photos permissions") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    LabeledContent("Photo uploads", value: "None")
                }
                Section {
                    Button { showingLab = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Research lab")
                            Text("Watermark benchmarks, screenshot recovery and JSON export").font(.footnote).foregroundStyle(ProofCamTheme.secondary)
                        }
                    }
                } header: { Text("Research") } footer: {
                    Text("For testing how watermarks survive re-saving. Results are measurements, not proof of authenticity.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")
                }
            }
            .scrollContentBackground(.hidden).background(ProofCamTheme.background)
            .foregroundStyle(ProofCamTheme.text)
            .navigationTitle("Settings").tint(ProofCamTheme.accent)
        }
        .sheet(isPresented: $showingGuide) { IntroductionScreen(completionTitle: "Done") { showingGuide = false } }
        .sheet(isPresented: $showingLab) { ResearchView() }
    }
}

struct IntroductionScreen: View {
    var completionTitle = "Open camera"
    let completed: () -> Void
    @State private var page = 0
    private let pages: [(tab: String, title: String, body: String, note: String)] = [
        ("Problem", "Photos change as they travel.",
         "A resident photographs a flooded storm drain. By the time it reaches a council meeting, it has been forwarded, cropped and screenshotted.",
         "ProofCam is for student journalists, residents, researchers and field teams who document what happens where they live."),
        ("Proof", "The proof rides inside the photo.",
         "A Secure Enclave key signs the image’s SHA-256 fingerprint. That signed record is embedded directly in the JPEG.",
         "Share the original JPEG to keep the image and its proof together. No account is required."),
        ("Limits", "A match means unchanged.",
         "Anyone with the original file can open Verify and check whether the image still matches its embedded proof.",
         "A match does not prove the event happened as described, or who took the photo.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ProofCamMark()
                Spacer()
                if page < pages.count - 1 { Button("Skip") { completed() }.tint(ProofCamTheme.accent).frame(minHeight: 44) }
            }
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Button { withAnimation { page = index } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(index <= page ? ProofCamTheme.accent : ProofCamTheme.border).frame(height: 3)
                            Text(pages[index].tab).font(.footnote.weight(.medium))
                                .foregroundStyle(index == page ? ProofCamTheme.text : ProofCamTheme.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(pages[index].tab), page \(index + 1) of \(pages.count)")
                        .accessibilityAddTraits(index == page ? .isSelected : [])
                }
            }.padding(.top, 12)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            IntroArtwork(page: index, active: page == index)
                                .frame(height: 240).frame(maxWidth: .infinity)
                                .background(ProofCamTheme.brandGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            Text(pages[index].title).font(ProofCamType.display(32, relativeTo: .largeTitle))
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 24)
                            Text(pages[index].body).font(.body).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                            Text(pages[index].note).font(.subheadline).foregroundStyle(ProofCamTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                        }.frame(maxWidth: 500, alignment: .leading).padding(.top, 16).padding(.bottom, 24)
                    }.scrollIndicators(.hidden).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 12) {
                Button {
                    if page == pages.count - 1 { completed() }
                    else { withAnimation { page += 1 } }
                } label: { Text(page == pages.count - 1 ? completionTitle : "Continue") }
                    .buttonStyle(PrimaryButtonStyle())
                Text("No account. Photos stay on your iPhone.").font(.caption).foregroundStyle(ProofCamTheme.secondary)
            }
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
        .background(ProofCamTheme.atmosphereGradient.ignoresSafeArea())
        .foregroundStyle(ProofCamTheme.text)
    }
}

/// Artwork for each introduction page, drawn with shapes rather than stock imagery.
private struct IntroArtwork: View {
    let page: Int
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var aligned = false
    @State private var tucked = false
    private let ink = Color(red: 0x20 / 255, green: 0x2C / 255, blue: 0x38 / 255)
    var body: some View {
        ZStack {
            switch page {
            case 0:
                printCard("Screenshot", symbol: "rectangle.dashed", angle: 7).offset(x: 104, y: -10)
                printCard("Forwarded", symbol: "crop", angle: 2).offset(x: 0, y: 8)
                printCard("Original", symbol: "photo", angle: -5).offset(x: -104, y: -6)
            case 1:
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHA-256").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text("P-256 · Secure Enclave").font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(ink).padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                .rotationEffect(.degrees(tucked ? 4 : 8))
                .offset(x: tucked ? 46 : 96, y: tucked ? -40 : 36)
                printCard("Proof inside", symbol: "photo", angle: -3).offset(x: -30)
            default:
                RegistrationMark().stroke(ink, lineWidth: 2).frame(width: 140, height: 140)
                RegistrationMark().stroke(Color.white, lineWidth: 2).frame(width: 140, height: 140)
                    .offset(x: aligned ? 0 : 34, y: aligned ? 0 : -22)
            }
        }
        .accessibilityHidden(true)
        .onChange(of: active, initial: true) { _, isActive in
            guard isActive else { aligned = false; tucked = false; return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1).delay(0.35)) { aligned = true; tucked = true }
        }
    }
    private func printCard(_ caption: String, symbol: String, angle: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(ink.opacity(0.7))
                .frame(width: 86, height: 104).background(Color(red: 0xDC / 255, green: 0xE6 / 255, blue: 0xEE / 255))
            Text(caption).font(.caption2.weight(.medium)).foregroundStyle(ink.opacity(0.75))
        }
        .padding(6).background(Color.white, in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        .rotationEffect(.degrees(angle))
    }
}
