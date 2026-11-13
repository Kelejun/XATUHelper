import SwiftUI
import UIKit

struct CourseSearchToolbarBehavior: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.1, *) {
            content.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
    }
}

struct CourseNativeSearch: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.campusSidebarToggle) private var sidebarToggle
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if sidebarToggle != nil || UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular {
            content.background {
                CourseNavigationSearch(text: $text).frame(width: 0, height: 0)
            }
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索课程名称")
        }
    }
}

private struct CourseNavigationSearch: UIViewControllerRepresentable {
    @Binding var text: String

    func makeUIViewController(context: Context) -> Controller {
        Controller(text: $text)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.text = $text
        if controller.search.searchBar.text != text {
            controller.search.searchBar.text = text
        }
        DispatchQueue.main.async { controller.attachSearch() }
    }

    final class Controller: UIViewController, UISearchResultsUpdating {
        var text: Binding<String>
        let search = UISearchController(searchResultsController: nil)
        private weak var searchOwner: UIViewController?

        init(text: Binding<String>) {
            self.text = text
            super.init(nibName: nil, bundle: nil)
            search.searchResultsUpdater = self
            search.obscuresBackgroundDuringPresentation = false
            search.hidesNavigationBarDuringPresentation = false
            search.searchBar.placeholder = "搜索课程名称"
            search.searchBar.text = text.wrappedValue
            search.searchBar.autocorrectionType = .no
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachSearch()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            attachSearch()
        }

        func attachSearch() {
            guard isViewLoaded, view.window != nil, let navigation = navigationController else { return }
            var owner: UIViewController = self
            while let parent = owner.parent, parent !== navigation {
                owner = parent
            }
            guard navigation.topViewController === owner,
                  owner.navigationItem.searchController !== search else { return }
            owner.definesPresentationContext = true
            owner.navigationItem.searchController = search
            owner.navigationItem.hidesSearchBarWhenScrolling = false
            if #available(iOS 26.0, *) {
                owner.navigationItem.preferredSearchBarPlacement = .integrated
                owner.navigationItem.searchBarPlacementAllowsToolbarIntegration = false
                owner.navigationItem.searchBarPlacementAllowsExternalIntegration = false
            } else {
                owner.navigationItem.preferredSearchBarPlacement = .inline
            }
            navigation.navigationBar.setNeedsLayout()
            searchOwner = owner
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            search.isActive = false
            if let owner = searchOwner, owner.navigationItem.searchController === search {
                owner.navigationItem.searchController = nil
            }
            searchOwner = nil
        }

        func updateSearchResults(for searchController: UISearchController) {
            let value = searchController.searchBar.text ?? ""
            if text.wrappedValue != value { text.wrappedValue = value }
        }
    }
}
