import UIKit

final class OfflineLibraryViewController: UITableViewController {
    private let store: OfflineGameStore
    private let openGame: (SavedOfflineGame) -> Void
    private var games: [SavedOfflineGame] = []

    init(store: OfflineGameStore, openGame: @escaping (SavedOfflineGame) -> Void) {
        self.store = store
        self.openGame = openGame
        super.init(style: .insetGrouped)
    }

    required init?(coder _: NSCoder) {
        fatalError("Use programmatic initialization")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Сохранённые игры"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        tableView.accessibilityIdentifier = "ugames.offline.library"
        refresh()
    }

    private func refresh() {
        do { games = try store.games() } catch { games = [] }
        if games.isEmpty {
            let label = UILabel()
            label.text = "Здесь будут игры без интернета.\n\nОткрой игру с интернетом, дождись загрузки и выбери «Сохранить для оффлайна» в меню."
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            let container = UIView()
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            tableView.backgroundView = container
        } else {
            tableView.backgroundView = nil
        }
        tableView.reloadData()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        games.count
    }

    override func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let game = games[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = game.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.text = ByteCountFormatter.string(
            fromByteCount: game.bytes,
            countStyle: .file
        ) + " · Без интернета"
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.imageView?.image = UIImage(systemName: "arrow.down.circle.fill")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let game = games[indexPath.row]
        dismiss(animated: true) { self.openGame(game) }
    }

    override func tableView(
        _: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        do { try store.delete(games[indexPath.row])
            refresh()
        } catch {
            let alert = UIAlertController(
                title: "Не удалось удалить игру",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "ОК", style: .default))
            present(alert, animated: true)
        }
    }
}
