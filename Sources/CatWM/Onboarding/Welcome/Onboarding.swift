import AppKit
import CatWMKit
import SwiftUI

@MainActor final class Onboarding {
    static let shared = Onboarding()

    static var isDone: Bool { Instance.defaults.bool(forKey: DefaultsKey.didOnboard) }
    static var isStarted: Bool { Instance.defaults.bool(forKey: DefaultsKey.onboardingStarted) }

    weak var statusButton: NSStatusBarButton? {
        didSet { MenuBarTip.shared.statusButton = statusButton }
    }
    var welcome: CatWMPanel?
    let welcomeModel = WelcomeModel()
    var poll: Timer?
    var openedLoginItems = false

    var isRunning: Bool { welcome != nil }

    static func shouldShow(firstRun: Bool, trusted: Bool, done: Bool = isDone, started: Bool = isStarted) -> Bool {
        !done && (firstRun || !trusted || started)
    }

    func start() {
        guard !isRunning else { return }
        Instance.defaults.set(true, forKey: DefaultsKey.onboardingStarted)
        guard let screen = CatWMPanel.pointerScreen() else { return }
        makeWelcome(on: screen)
        showWelcome()
    }

    private func makeWelcome(on screen: NSScreen) {
        welcomeModel.page = .permissions
        welcomeModel.style = KeyStyle.current
        welcomeModel.allowAccessibility = { Permission.accessibility.request() }
        welcomeModel.allowInputMonitoring = { Permission.inputMonitoring.request() }
        welcomeModel.allowScreenRecording = { Permission.screenRecording.request() }
        welcomeModel.allowFullDiskAccess = { Permission.fullDiskAccess.request() }
        welcomeModel.takeTestImage = { [weak self] in
            Task { @MainActor in
                guard await ScreenRecording.shared.takeTestImage() else { return }
                self?.welcomeModel.screenTestDone = true
                self?.welcome?.makeKeyAndOrderFront(nil)
            }
        }
        welcomeModel.allowLogin = { [weak self] in
            LoginItem.shared.set(true)
            if !LoginItem.shared.isEnabled {
                self?.openedLoginItems = true
                LoginItem.shared.openSettings()
            }
        }
        PermissionGuide.shared.onGranted = { [weak self] in self?.welcome?.makeKeyAndOrderFront(nil) }
        welcomeModel.skip = { [weak self] in self?.finish() }
        welcomeModel.next = { [weak self] in
            guard Permission.accessibility.isGranted else { Permission.accessibility.request(); return }
            self?.welcomeModel.page = .keys
        }
        welcomeModel.done = { [weak self] in
            guard let self else { return }
            guard Permission.accessibility.isGranted else { welcomeModel.page = .permissions; return }
            if let style = welcomeModel.style, style != KeyStyle.current,
               let config = SettingsWindow.shared.library.config(id: style.configID) {
                SettingsWindow.shared.library.select(config)
            }
            finish()
        }
        refreshWelcome()
        let host = CatWMHostingView(rootView: WelcomeView(model: welcomeModel))
        let panel = CatWMPanel(role: .card(.normal),
                              frame: CatWMPanel.frame(size: host.fittingSize, on: screen, anchor: .center(dy: -12),
                                                     inset: EdgeInsets(all: WelcomeView.margin)))
        panel.onClose = { [weak self] in self?.welcomeModel.skip() }
        panel.contentView = host
        panel.isMovableByWindowBackground = true
        welcome = panel
    }

    private func refreshWelcome() {
        let accessibility = Permission.accessibility.isGranted, login = LoginItem.shared.isEnabled
        if welcomeModel.accessibility != accessibility { welcomeModel.accessibility = accessibility }
        let inputMonitoring = Permission.inputMonitoring.isGranted
        if welcomeModel.inputMonitoring != inputMonitoring { welcomeModel.inputMonitoring = inputMonitoring }
        let screenRecording = Permission.screenRecording.isGranted, screenTestDone = ScreenRecording.shared.isTestDone
        if welcomeModel.screenRecording != screenRecording { welcomeModel.screenRecording = screenRecording }
        if welcomeModel.screenTestDone != screenTestDone { welcomeModel.screenTestDone = screenTestDone }
        let fullDiskAccess = Permission.fullDiskAccess.isGranted
        if welcomeModel.fullDiskAccess != fullDiskAccess { welcomeModel.fullDiskAccess = fullDiskAccess }
        if welcomeModel.login != login { welcomeModel.login = login }
        if login, openedLoginItems {
            openedLoginItems = false
            if accessibility { Permission.closeSettingsWindows() }
            welcome?.makeKeyAndOrderFront(nil)
        }
    }

    private func showWelcome() {
        guard let panel = welcome else { return }
        let end = panel.frame
        welcomeModel.landed = false
        panel.alphaValue = 0
        panel.setFrame(end.offsetBy(dx: 0, dy: -14), display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        Motion.group(0.5) {
            Motion.setAlpha(1, on: panel)
            Motion.setFrame(end, on: panel)
        }
        DispatchQueue.main.asyncAfter( // style-ok: the welcome panel finishes its entrance
            deadline: .now() + 0.3
        ) { [weak self] in self?.welcomeModel.landed = true }
        DispatchQueue.main.asyncAfter( // style-ok: the welcome entrance finishes before the tip
            deadline: .now() + 0.8
        ) { [weak self] in
            if self?.isRunning == true { MenuBarTip.shared.show() }
        }
        poll = Timer.onMain(every: 0.5, owner: self) { onboarding in
            LoginItem.shared.refresh { [weak onboarding] in onboarding?.refreshWelcome() }
        }
        poll?.tolerance = 0.1
    }

    private func finish() {
        poll?.invalidate()
        poll = nil
        PermissionGuide.shared.onGranted = nil
        guard let panel = welcome else { return }
        welcome = nil
        Motion.group(0.3, changes: { Motion.setAlpha(0, on: panel) }, completion: {
            panel.orderOut(nil)
            MenuBarTip.shared.hide()
            Instance.defaults.set(true, forKey: DefaultsKey.didOnboard)
            if Permission.accessibility.isGranted { HUD.shared.show("Tiling on", on: nil) }
        })
    }
}
