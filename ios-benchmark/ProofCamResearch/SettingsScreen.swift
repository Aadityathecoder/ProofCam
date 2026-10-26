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
                        Image(systemName: "camera.fill").font(.system(size: 27)).foregroundStyle(.black)
                            .frame(width: 58, height: 58).background(.yellow, in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ProofCam").font(.title2.bold())
                            Text("A record of your capture.").font(.subheadline).foregroundStyle(.secondary)
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
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.yellow)
                        Text("Always on").foregroundStyle(.yellow)
                    }.frame(height: 28)
                } header: { Text("Signatures") } footer: {
                    Text("Every completed photo is signed with a key protected by your iPhone’s Secure Enclave. A signature binds exact photo bytes; it does not establish camera origin or absence of AI. Registration remains separate.")
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
            }.navigationTitle("Settings").tint(.yellow)
        }
        .sheet(isPresented: $showingGuide) { IntroductionScreen(completionTitle: "Done") { showingGuide = false } }
    }
}

struct IntroductionScreen: View {
    var completionTitle = "Open camera"
    let completed: () -> Void
    @State private var page = 0
    private let pages: [(symbol: String, eyebrow: String, title: String, body: String, note: String)] = [
        ("camera.aperture", "MEET PROOFCAM", "Your camera.\nWith a record.",
         "Take a photo. ProofCam signs the saved image on your iPhone, so its exact bytes can be checked later.",
         "For journalists, researchers, field teams, and anyone documenting something that matters."),
        ("signature", "CAPTURE & KEEP", "Take it.\nSign it. Save it.",
         "Open Capture and press the shutter. Each completed photo is cryptographically signed, kept in ProofCam, and saved to your camera roll by default.",
         "Tap the thumbnail to review photos or share a photo with its signature. Choose your saving preferences in Settings."),
        ("checkmark.shield", "VERIFY WITH CONTEXT", "Check the photo.\nKnow the limits.",
         "In Verify, choose an original photo. ProofCam checks its saved signature. For a photo from someone else, import their signature too.",
         "Edits and re-encoding can change the bytes. A valid signature is not proof of camera origin or that an image is free of AI.")
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("PROOFCAM", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                Spacer()
                Text("\(page + 1) / \(pages.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.top, 24)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ZStack {
                                Circle().stroke(.yellow.opacity(0.08), lineWidth: 1).frame(width: 224, height: 224)
                                Circle().fill(.yellow.opacity(0.07)).frame(width: 174, height: 174)
                                Image(systemName: pages[index].symbol).font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.yellow)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                            Text(pages[index].eyebrow).font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundStyle(.yellow)
                            Text(pages[index].title).font(.system(size: 39, weight: .semibold, design: .rounded)).tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                            Text(pages[index].body).font(.system(size: 17)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                            Text(pages[index].note).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: 500).padding(.horizontal, 28).padding(.bottom, 24)
                    }.tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 20) {
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule().fill(page == index ? .yellow : .white.opacity(0.2)).frame(width: page == index ? 22 : 6, height: 6)
                    }
                }.accessibilityLabel("Introduction page \(page + 1) of \(pages.count)")
                Button {
                    if page == pages.count - 1 { completed() }
                    else { withAnimation { page += 1 } }
                } label: {
                    HStack { Spacer(); Text(page == pages.count - 1 ? completionTitle : "Continue").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }
                        .padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                Text("No account. Photos are processed on your device.").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.bottom, 24)
        }.background(Color(white: 0.035)).preferredColorScheme(.dark)
    }
}
