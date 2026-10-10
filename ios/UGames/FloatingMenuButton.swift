import UIKit

/// A small hit target: the rest of the game surface receives touches directly.
final class FloatingMenuButton: UIButton {
    private let defaults: UserDefaults
    private var position: CGPoint
    private var dragOrigin = CGPoint.zero
    private var placementArea = CGRect.zero
    private static let xKey = "gameMenu.x"
    private static let yKey = "gameMenu.y"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        position = CGPoint(
            x: defaults.object(forKey: Self.xKey) as? Double ?? 1,
            y: defaults.object(forKey: Self.yKey) as? Double ?? 0.2
        )
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        tintColor = .white
        layer.cornerRadius = 22
        setImage(UIImage(systemName: "ellipsis"), for: .normal)
        accessibilityLabel = "Меню"
        accessibilityHint = "Назад, каталог и обновление. Кнопку можно перетащить."
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag)))
    }

    required init?(coder _: NSCoder) {
        fatalError("Use programmatic initialization")
    }

    func restorePosition() {
        position = CGPoint(
            x: defaults.object(forKey: Self.xKey) as? Double ?? 1,
            y: defaults.object(forKey: Self.yKey) as? Double ?? 0.2
        )
    }

    func place(in safeArea: CGRect) {
        placementArea = safeArea
        let area = safeArea.insetBy(dx: 8, dy: 8)
        let width = max(0, area.width - bounds.width)
        let height = max(0, area.height - bounds.height)
        frame.origin = CGPoint(
            x: area.minX + width * min(1, max(0, position.x)),
            y: area.minY + height * min(1, max(0, position.y))
        )
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        if gesture.state == .began {
            dragOrigin = frame.origin
            isHighlighted = false
        }
        let area = placementArea.insetBy(dx: 8, dy: 8)
        let translation = gesture.translation(in: parent)
        let width = max(0, area.width - bounds.width)
        let height = max(0, area.height - bounds.height)
        let x = min(width, max(0, dragOrigin.x + translation.x - area.minX))
        let y = min(height, max(0, dragOrigin.y + translation.y - area.minY))
        position = CGPoint(x: width > 0 ? x / width : 0, y: height > 0 ? y / height : 0)
        place(in: placementArea)
        if gesture.state == .ended || gesture.state == .cancelled {
            defaults.set(Double(position.x), forKey: Self.xKey)
            defaults.set(Double(position.y), forKey: Self.yKey)
        }
    }
}
