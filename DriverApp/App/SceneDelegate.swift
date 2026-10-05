//
//  SceneDelegate.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let navigationController = UINavigationController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController

        let compositionRoot = CompositionRoot(configuration: .staging)
        let developmentHomeFactory = CompositionRoot(configuration: .mock).makeHomeFactory()
        let coordinator = AppCoordinator(
            navigationController: navigationController,
            authFactory: compositionRoot.makeAuthFactory(),
            homeFactory: compositionRoot.makeHomeFactory(),
            developmentHomeFactory: developmentHomeFactory,
            driverProfileFactory: compositionRoot.makeDriverProfileFactory(),
            driverEntryFactory: compositionRoot.makeDriverEntryFactory(),
            tripFactory: compositionRoot.makeTripFactory(),
            restoreSession: compositionRoot.makeRestoreSessionUseCase(),
            loadDriverProfile: compositionRoot.makeLoadDriverProfileUseCase(),
            logout: compositionRoot.makeLogoutUseCase(),
            clearDriverSession: compositionRoot.makeClearDriverSessionUseCase()
        )

        self.window = window
        self.coordinator = coordinator
        window.makeKeyAndVisible()
        coordinator.start()
    }
}
