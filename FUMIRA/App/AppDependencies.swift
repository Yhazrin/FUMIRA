import Foundation

struct AppDependencies {
    let camera: any CameraService
    let cameraPreview: any CameraPreviewFactory
    let hardware: any HardwareController
    let understanding: any ImageUnderstandingProvider
    let story: any StoryProvider
    let generation: any GenerationProvider
    let modelCatalog: any AIModelCatalogProvider
    let modelConfigurationStore: any AIModelConfigurationStore
    let storage: any PosterStorage
    let haptics: any HapticsClient

    static var preview: AppDependencies {
        AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(),
            story: MockStoryProvider(),
            generation: MockGenerationProvider(),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: UserDefaultsAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient()
        )
    }

    static var test: AppDependencies {
        AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(stepDelay: .zero),
            story: MockStoryProvider(stepDelay: .zero),
            generation: MockGenerationProvider(stepDelay: .zero),
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: InMemoryAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient()
        )
    }

    static var runtime: AppDependencies {
        let generation: any GenerationProvider = {
            if let baseURL = FUMIRAAPIConfiguration.baseURL {
                return RemoteGenerationProvider(baseURL: baseURL)
            }
            return MockGenerationProvider()
        }()

        #if targetEnvironment(simulator)
        return AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(),
            story: MockStoryProvider(),
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: UserDefaultsAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient()
        )
        #else
        let liveCamera = LiveCameraService()
        return AppDependencies(
            camera: liveCamera,
            cameraPreview: liveCamera,
            hardware: MockHardwareController(),
            understanding: MockImageUnderstandingProvider(),
            story: MockStoryProvider(),
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: UserDefaultsAIModelConfigurationStore(),
            storage: MockPosterStorage(),
            haptics: MockHapticsClient()
        )
        #endif
    }
}
