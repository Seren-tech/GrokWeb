import UIKit
import WebKit

final class PopupViewController: UIViewController {
    let webView: WKWebView
    var onDone: ((PopupViewController) -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: g.topAnchor),
            webView.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: g.trailingAnchor)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(done))
    }

    @objc private func done() {
        let cb = onDone
        navigationController?.dismiss(animated: true) { cb?(self) }
    }
}
