import UIKit
import WebKit

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

final class MainViewController: UIViewController {
    private struct Popup {
        let web: WKWebView
        let nav: UINavigationController
        let vc: PopupViewController
    }

    private var webView: WKWebView!
    private let menuButton = UIButton(type: .system)
    private let logOverlay = LogOverlayView()
    private let refreshControl = UIRefreshControl()
    private var popups: [Popup] = []
    private var menuPlaced = false
    private let defaults = UserDefaults.standard

    private var siteIndex: Int {
        get { min(max(defaults.integer(forKey: "siteIndex"), 0), Config.sites.count - 1) }
        set { defaults.set(newValue, forKey: "siteIndex") }
    }
    private var uaIndex: Int {
        get { min(max(defaults.integer(forKey: "uaIndex"), 0), Config.userAgentPresets.count - 1) }
        set { defaults.set(newValue, forKey: "uaIndex") }
    }
    private var currentUserAgent: String? { Config.userAgentPresets[uaIndex].value }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = currentUserAgent
        webView.underPageBackgroundColor = .systemBackground
        view.addSubview(webView)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: g.topAnchor),
            webView.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: g.trailingAnchor)
        ])

        // Pull to refresh
        refreshControl.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        // Triple-tap opens the log overlay
        let triple = UITapGestureRecognizer(target: self, action: #selector(toggleLog))
        triple.numberOfTapsRequired = 3
        triple.cancelsTouchesInView = false
        triple.delegate = self
        webView.addGestureRecognizer(triple)

        // Floating menu button
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .white
        menuButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        menuButton.layer.cornerRadius = 20
        menuButton.alpha = 0.6
        menuButton.accessibilityLabel = "Menu"
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = buildMenu()
        menuButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragMenu(_:))))
        view.addSubview(menuButton)

        // Log overlay
        logOverlay.translatesAutoresizingMaskIntoConstraints = false
        logOverlay.onClose = { [weak self] in self?.logOverlay.hide() }
        view.addSubview(logOverlay)
        NSLayoutConstraint.activate([
            logOverlay.topAnchor.constraint(equalTo: g.topAnchor),
            logOverlay.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            logOverlay.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            logOverlay.trailingAnchor.constraint(equalTo: g.trailingAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide),
                                               name: UIResponder.keyboardDidHideNotification, object: nil)

        LogStore.shared.add("native", "UA: \(currentUserAgent ?? "WebView native")")
        webView.load(URLRequest(url: Config.sites[siteIndex].url))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !menuPlaced && view.bounds.width > 0 {
            menuButton.frame = CGRect(x: view.safeAreaInsets.left + 6,
                                      y: view.bounds.height * 0.45, width: 40, height: 40)
            menuPlaced = true
        }
    }

    // MARK: - Setup

    private func makeConfiguration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = WKWebsiteDataStore.default()   // persistent: login survives restarts
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        c.preferences.javaScriptCanOpenWindowsAutomatically = true
        c.userContentController.addUserScript(UserScripts.main)
        c.userContentController.add(WeakScriptHandler(self), name: "nativeLog")
        return c
    }

    // MARK: - Actions

    @objc private func pullRefresh() {
        reloadPage()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    @objc private func toggleLog() {
        if logOverlay.isHidden { logOverlay.show() } else { logOverlay.hide() }
    }

    @objc private func dragMenu(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        let b = view.bounds.inset(by: view.safeAreaInsets)
        var c = CGPoint(x: menuButton.center.x + t.x, y: menuButton.center.y + t.y)
        c.x = min(max(c.x, b.minX + 20), b.maxX - 20)
        c.y = min(max(c.y, b.minY + 20), b.maxY - 20)
        menuButton.center = c
        g.setTranslation(.zero, in: view)
    }

    // Prevents the page from staying shifted/zoomed after the keyboard closes.
    @objc private func keyboardDidHide() {
        let sv = webView.scrollView
        let maxY = max(-sv.adjustedContentInset.top,
                       sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
        var offset = sv.contentOffset
        if offset.y > maxY { offset.y = maxY }
        if sv.contentSize.width <= sv.bounds.width + 1 { offset.x = 0 }
        if offset != sv.contentOffset { sv.setContentOffset(offset, animated: false) }
        if abs(sv.zoomScale - 1.0) > 0.01 { sv.setZoomScale(1.0, animated: true) }
    }

    private func reloadPage() {
        if webView.url == nil {
            webView.load(URLRequest(url: Config.sites[siteIndex].url))
        } else {
            webView.reload()
        }
    }

    private func switchSite(_ index: Int) {
        siteIndex = index
        webView.load(URLRequest(url: Config.sites[index].url))
        menuButton.menu = buildMenu()
    }

    private func switchUserAgent(_ index: Int) {
        uaIndex = index
        webView.customUserAgent = currentUserAgent
        popups.forEach { $0.web.customUserAgent = currentUserAgent }
        LogStore.shared.add("native", "UA switched: \(currentUserAgent ?? "WebView native")")
        menuButton.menu = buildMenu()
        reloadPage()
    }

    private func confirmClearData() {
        let a = UIAlertController(title: "Clear website data?",
                                  message: "Cookies, local storage and caches will be removed. You will be logged out.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in self?.clearData() })
        topPresenter().present(a, animated: true)
    }

    private func clearData() {
        let epoch = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: epoch) { [weak self] in
            guard let self = self else { return }
            HTTPCookieStorage.shared.removeCookies(since: epoch)
            LogStore.shared.add("native", "Website data cleared")
            self.webView.load(URLRequest(url: Config.sites[self.siteIndex].url))
        }
    }

    private func buildMenu() -> UIMenu {
        let reload = UIAction(title: "Reload", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.reloadPage()
        }

        let siteActions = Config.sites.enumerated().map { (i, s) in
            UIAction(title: s.name, state: i == siteIndex ? .on : .off) { [weak self] _ in
                self?.switchSite(i)
            }
        }
        let sitesMenu = UIMenu(title: "Site", image: UIImage(systemName: "globe"), children: siteActions)

        let uaActions = Config.userAgentPresets.enumerated().map { (i, p) in
            UIAction(title: p.name, state: i == uaIndex ? .on : .off) { [weak self] _ in
                self?.switchUserAgent(i)
            }
        }
        let uaMenu = UIMenu(title: "User-Agent", image: UIImage(systemName: "person.crop.square"), children: uaActions)

        let log = UIAction(title: "Debug log", image: UIImage(systemName: "ladybug")) { [weak self] _ in
            self?.toggleLog()
        }
        let clear = UIAction(title: "Clear website data", image: UIImage(systemName: "trash"),
                             attributes: .destructive) { [weak self] _ in
            self?.confirmClearData()
        }
        return UIMenu(title: "", children: [reload, sitesMenu, uaMenu, log, clear])
    }

    private func topPresenter() -> UIViewController {
        var vc: UIViewController = self
        while let p = vc.presentedViewController { vc = p }
        return vc
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func openPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        // Must use the configuration WebKit hands us so window.opener / postMessage work for OAuth.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = currentUserAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.allowsBackForwardNavigationGestures = true
        popup.underPageBackgroundColor = .systemBackground

        let vc = PopupViewController(webView: popup)
        vc.onDone = { [weak self] done in self?.popups.removeAll { $0.vc === done } }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        popups.append(Popup(web: popup, nav: nav, vc: vc))
        topPresenter().present(nav, animated: true)
        return popup
    }
}

// MARK: - WKScriptMessageHandler

extension MainViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }
        LogStore.shared.add(d["level"] as? String ?? "log", d["msg"] as? String ?? "")
    }
}

// MARK: - WKNavigationDelegate

extension MainViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "http" || scheme == "https" {
            // Only user-tapped links to foreign hosts go to Safari; redirects/OAuth chains stay in-app.
            if navigationAction.navigationType == .linkActivated,
               navigationAction.targetFrame?.isMainFrame ?? true,
               let host = url.host, !Config.isInAppHost(host) {
                openExternally(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        } else if ["about", "blob", "data", "file", "javascript"].contains(scheme) {
            decisionHandler(.allow)
        } else {
            openExternally(url)   // tel:, mailto:, custom schemes
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        if let p = popups.first(where: { $0.web === webView }) {
            p.vc.title = webView.url?.host
        }
        LogStore.shared.add("native", "Loaded: \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        LogStore.shared.add("native", "Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        if (error as NSError).code == NSURLErrorCancelled { return }
        LogStore.shared.add("native", "Load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        LogStore.shared.add("native", "Web content process terminated, reloading")
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension MainViewController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Plain <a target="_blank"> link: stay in the same view, or hand off to Safari.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            let scheme = url.scheme?.lowercased() ?? ""
            if (scheme == "http" || scheme == "https"), let host = url.host, Config.isInAppHost(host) {
                webView.load(navigationAction.request)
            } else {
                openExternally(url)
            }
            return nil
        }
        // Script-driven window.open (OAuth popups etc.): modal web view sharing the opener's context.
        return openPopup(configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let i = popups.firstIndex(where: { $0.web === webView }) {
            let p = popups.remove(at: i)
            p.nav.dismiss(animated: true)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Config.isInAppHost(origin.host) ? .grant : .prompt)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        topPresenter().present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        topPresenter().present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(a.textFields?.first?.text)
        })
        topPresenter().present(a, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MainViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
