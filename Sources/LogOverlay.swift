import UIKit

final class LogStore {
    static let shared = LogStore()
    private(set) var lines: [String] = []
    var onChange: (() -> Void)?
    private let maxLines = 3000
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func add(_ level: String, _ message: String) {
        lines.append("[\(formatter.string(from: Date()))] \(level.uppercased()): \(message)")
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        onChange?()
    }

    func clear() {
        lines.removeAll()
        onChange?()
    }

    var text: String { lines.joined(separator: "\n") }
}

final class LogOverlayView: UIView {
    var onClose: (() -> Void)?
    private let textView = UITextView()
    private let copyButton = UIButton(type: .system)
    private var refreshScheduled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.9)
        isHidden = true

        let title = UILabel()
        title.text = "Debug log"
        title.textColor = .white
        title.font = .boldSystemFont(ofSize: 15)

        let clearButton = UIButton(type: .system)
        let closeButton = UIButton(type: .system)
        copyButton.setTitle("Copy log", for: .normal)
        clearButton.setTitle("Clear", for: .normal)
        closeButton.setTitle("Close", for: .normal)
        [copyButton, clearButton, closeButton].forEach { $0.tintColor = .systemTeal }

        copyButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            UIPasteboard.general.string = LogStore.shared.text
            self.copyButton.setTitle("Copied!", for: .normal)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.copyButton.setTitle("Copy log", for: .normal)
            }
        }, for: .touchUpInside)
        clearButton.addAction(UIAction { _ in LogStore.shared.clear() }, for: .touchUpInside)
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), copyButton, clearButton, closeButton])
        header.axis = .horizontal
        header.spacing = 14
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textColor = UIColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1)
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(textView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        LogStore.shared.onChange = { [weak self] in self?.scheduleRefresh() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        isHidden = false
        refresh()
    }

    func hide() { isHidden = true }

    private func scheduleRefresh() {
        guard !isHidden, !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        textView.text = LogStore.shared.text
        let length = (textView.text as NSString).length
        if length > 0 { textView.scrollRangeToVisible(NSRange(location: length - 1, length: 1)) }
    }
}
