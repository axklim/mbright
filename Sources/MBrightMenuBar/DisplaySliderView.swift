import AppKit

/// One display in the menu: name, current percentage, and a slider.
@MainActor
final class DisplaySliderView: NSView {
    static let preferredSize = NSSize(width: 260, height: 54)

    let row: DisplayRow
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let onChange: (Int) -> Void

    init(row: DisplayRow, onChange: @escaping (Int) -> Void) {
        self.row = row
        self.onChange = onChange
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))

        nameLabel.stringValue = row.name
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        setValueText(row.percent.map { "\($0)%" } ?? row.detail ?? "")

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.controlSize = .small
        if let percent = row.percent {
            slider.integerValue = percent
        } else {
            slider.isEnabled = false
        }

        for view in [nameLabel, valueLabel, slider] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(percent: Int) {
        guard !slider.cell!.isHighlighted else { return }
        slider.integerValue = percent
        setValueText("\(percent)%")
    }

    private func setValueText(_ text: String) {
        valueLabel.stringValue = text
    }

    @objc private func sliderChanged() {
        let percent = slider.integerValue
        setValueText("\(percent)%")
        onChange(percent)
    }
}
