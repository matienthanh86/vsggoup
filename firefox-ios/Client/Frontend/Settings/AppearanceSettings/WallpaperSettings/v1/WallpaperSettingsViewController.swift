// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import PhotosUI
import UIKit

class WallpaperSettingsViewController: WallpaperBaseViewController, Themeable {
    @MainActor
    private enum UX {
        static let cardWidth: CGFloat = UIDevice().isTinyFormFactor ? 88 : 97
        static let cardHeight: CGFloat = UIDevice().isTinyFormFactor ? 80 : 88
        static let inset: CGFloat = 8
        static let cardShadowHeight: CGFloat = 14
        static let sectionBottomInset: CGFloat = 16
    }

    private var viewModel: WallpaperSettingsViewModel
    var notificationCenter: NotificationProtocol
    var themeManager: ThemeManager
    var themeListenerCancellable: Any?
    private var logger: Logger
    weak var settingsDelegate: SettingsDelegate?
    let windowUUID: WindowUUID
    var currentWindowUUID: UUID? { windowUUID }

    var shouldUsePrivateOverride: Bool { return true }
    var shouldBeInPrivateTheme: Bool { return false }

    private func currentTheme() -> Theme {
        return themeManager.resolveTheme(for: windowUUID,
                                         shouldUsePrivateOverride: shouldUsePrivateOverride,
                                         shouldBeInPrivateTheme: shouldBeInPrivateTheme)
    }

    // Views
    private lazy var contentView: UIView = .build { _ in }

    private lazy var customWallpaperBar: UIStackView = .build { stack in
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
    }

    private lazy var choosePhotoButton: UIButton = .build { button in
        var config = UIButton.Configuration.filled()
        config.title = Locale.current.language.languageCode?.identifier == "vi"
            ? "Chọn ảnh từ thư viện"
            : "Choose from Photos"
        config.image = UIImage(systemName: "photo.on.rectangle")
        config.imagePadding = 8
        config.cornerStyle = .medium
        button.configuration = config
        button.addTarget(self, action: #selector(self.choosePhotoTapped), for: .touchUpInside)
    }

    private lazy var resetDefaultButton: UIButton = .build { button in
        var config = UIButton.Configuration.tinted()
        config.title = Locale.current.language.languageCode?.identifier == "vi"
            ? "Mặc định"
            : "Reset Default"
        config.image = UIImage(systemName: "arrow.counterclockwise")
        config.imagePadding = 6
        config.cornerStyle = .medium
        button.configuration = config
        button.addTarget(self, action: #selector(self.resetDefaultTapped), for: .touchUpInside)
    }

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero,
                                              collectionViewLayout: getCompositionalLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self

        collectionView.register(
            WallpaperCollectionViewCell.self,
            forCellWithReuseIdentifier: WallpaperCollectionViewCell.cellIdentifier)
        collectionView.register(WallpaperSettingsHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: WallpaperSettingsHeaderView.cellIdentifier)
        return collectionView
    }()

    // MARK: - Initializers
    init(viewModel: WallpaperSettingsViewModel,
         windowUUID: WindowUUID,
         notificationCenter: NotificationProtocol = NotificationCenter.default,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         logger: Logger = DefaultLogger.shared) {
        self.viewModel = viewModel
        self.windowUUID = windowUUID
        self.notificationCenter = notificationCenter
        self.themeManager = themeManager
        self.logger = logger
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View setup & lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [UIContentSizeCategory.didChangeNotification]
        )

        listenForThemeChanges(withNotificationCenter: notificationCenter)
        applyTheme()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.removeAssetsOnDismiss()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()

        collectionView.selectItem(at: viewModel.selectedIndexPath, animated: false, scrollPosition: [])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Fixes bug where selection state gets lost when switching themes
        collectionView.selectItem(at: viewModel.selectedIndexPath, animated: false, scrollPosition: [])
    }

    override func updateOnRotation() {
        configureCollectionView()
    }

    func applyTheme() {
        contentView.backgroundColor = currentTheme().colors.layer5
    }
}

// MARK: - CollectionView Data Source
extension WallpaperSettingsViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return viewModel.numberOfSections
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.numberOfWallpapers(in: section)
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: WallpaperSettingsHeaderView.cellIdentifier,
                for: indexPath) as? WallpaperSettingsHeaderView,
              let headerViewModel = viewModel.sectionHeaderViewModel(for: indexPath.section, dismissView: { [weak self] in
                  self?.dismissView()
              })
        else { return UICollectionReusableView() }

        headerView.configure(viewModel: headerViewModel)
        return headerView
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WallpaperCollectionViewCell.cellIdentifier,
            for: indexPath) as? WallpaperCollectionViewCell,
              let cellViewModel = viewModel.cellViewModel(for: indexPath)
        else { return UICollectionViewCell() }

        cell.viewModel = cellViewModel
        cell.applyTheme(theme: currentTheme())
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        downloadAndSetWallpaper(at: indexPath)
    }
}

// MARK: - Private
private extension WallpaperSettingsViewController {
    func setupView() {
        configureCollectionView()

        customWallpaperBar.addArrangedSubview(choosePhotoButton)
        customWallpaperBar.addArrangedSubview(resetDefaultButton)

        contentView.addSubview(customWallpaperBar)
        contentView.addSubview(collectionView)
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            customWallpaperBar.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 12),
            customWallpaperBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            customWallpaperBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            customWallpaperBar.heightAnchor.constraint(equalToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: customWallpaperBar.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @objc
    func choosePhotoTapped() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc
    func resetDefaultTapped() {
        WallpaperManager().setCurrentWallpaper(to: Wallpaper.baseWallpaper) { [weak self] result in
            ensureMainThread {
                if case .success = result {
                    self?.showToast()
                }
            }
        }
    }

    func configureCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.collectionViewLayout = getCompositionalLayout()
    }

    func getCompositionalLayout() -> UICollectionViewCompositionalLayout {
        viewModel.updateSectionLayout(for: traitCollection)

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .vertical

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] ix, environment in
            guard let self else { return nil }

            let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(UX.cardWidth),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                   heightDimension: .absolute(UX.cardHeight))
            let subitemsCount = self.viewModel.sectionLayout.itemsPerRow
            let subItems: [NSCollectionLayoutItem] = Array(repeating: item, count: Int(subitemsCount))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                           subitems: subItems)
            group.interItemSpacing = .fixed(UX.inset)

            let section = NSCollectionLayoutSection(group: group)
            let width = environment.container.effectiveContentSize.width
            let inset = (width -
                         CGFloat(subitemsCount) * UX.cardWidth -
                         CGFloat(subitemsCount - 1) * UX.inset) / 2.0
            section.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                            leading: inset,
                                                            bottom: UX.sectionBottomInset,
                                                            trailing: inset)
            section.interGroupSpacing = UX.inset

            // Supplementary Item
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                    heightDimension: .estimated(38))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top)
            section.boundarySupplementaryItems = [header]

            return section
        }, configuration: config)

        return layout
    }

    func showToast() {
        let viewModel = ButtonToastViewModel(labelText: WallpaperSettingsViewModel.Constants.Strings.Toast.label,
                                             buttonText: WallpaperSettingsViewModel.Constants.Strings.Toast.button)
        let toast = ButtonToast(
            viewModel: viewModel,
            theme: currentTheme(),
            completion: { [weak self] buttonPressed in
                if buttonPressed { self?.dismissView() }
            })

        toast.showToast(viewController: self,
                        delay: Toast.UX.toastDelayBefore,
                        duration: Toast.UX.toastDismissAfter) { toast in
            [
                toast.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor,
                                               constant: Toast.UX.toastSidePadding),
                toast.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor,
                                                constant: -Toast.UX.toastSidePadding),
                toast.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
            ]
        }
    }

    func dismissView() {
        settingsDelegate?.didFinish()
        viewModel.selectHomepageTab()
    }

    func downloadAndSetWallpaper(at indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? WallpaperCollectionViewCell
            else { return }

        cell.showDownloading(true)

        viewModel.downloadAndSetWallpaper(at: indexPath) { [weak self] result in
            ensureMainThread {
                switch result {
                case .success:
                    self?.showToast()
                case .failure(let error):
                    self?.logger.log("Could not download and set wallpaper: \(error.localizedDescription)",
                                     level: .warning,
                                     category: .homepage)
                    self?.showError(error) { _ in
                        self?.downloadAndSetWallpaper(at: indexPath)
                    }
                }
                cell.showDownloading(false)
            }
        }
    }
}

// MARK: - Notifiable
extension WallpaperSettingsViewController: Notifiable {
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case UIContentSizeCategory.didChangeNotification:
            ensureMainThread {
                // Reload the entire collection view as the section headers are not adjusting their size correctly otherwise
                self.collectionView.reloadData()
            }
        default: break
        }
    }
}

// MARK: - PHPickerViewControllerDelegate
extension WallpaperSettingsViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }

        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            let customID = "customUserWallpaper"
            let customWallpaper = Wallpaper(
                id: customID,
                textColor: nil,
                cardColor: nil,
                logoTextColor: nil
            )
            let storageUtility = WallpaperStorageUtility()
            do {
                try storageUtility.store(image, withName: customWallpaper.thumbnailID)
                for imageType in WallpaperImageType.allCases {
                    try storageUtility.store(image, withName: customWallpaper.fileName(for: imageType))
                }
                ensureMainThread {
                    WallpaperManager().setCurrentWallpaper(to: customWallpaper) { result in
                        ensureMainThread {
                            if case .success = result {
                                self?.showToast()
                            }
                        }
                    }
                }
            } catch {
                self?.logger.log("Failed to save custom wallpaper: \(error.localizedDescription)",
                                 level: .warning,
                                 category: .homepage)
            }
        }
    }
}
