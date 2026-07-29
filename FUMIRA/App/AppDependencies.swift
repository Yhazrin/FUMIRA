import Foundation

struct AppDependencies {
    let camera: any CameraService
    let cameraPreview: any CameraPreviewFactory
    let cameraActivity: any CameraLiveActivityService
    let hardware: any HardwareController
    let understanding: any ImageUnderstandingProvider
    let story: any StoryProvider
    let generation: any GenerationProvider
    let modelCatalog: any AIModelCatalogProvider
    let modelConfigurationStore: any AIModelConfigurationStore
    let storage: any PosterStorage
    let haptics: any HapticsClient
    let motionField: any MotionFieldProviding
    let captureMotion: any CaptureMotionProviding
    let sceneLayerAnalyzer: any SceneLayerAnalyzing

    init(
        camera: any CameraService,
        cameraPreview: any CameraPreviewFactory,
        hardware: any HardwareController,
        understanding: any ImageUnderstandingProvider,
        story: any StoryProvider,
        generation: any GenerationProvider,
        modelCatalog: any AIModelCatalogProvider,
        modelConfigurationStore: any AIModelConfigurationStore,
        storage: any PosterStorage,
        haptics: any HapticsClient,
        motionField: any MotionFieldProviding,
        captureMotion: any CaptureMotionProviding = MockCaptureMotionService(),
        sceneLayerAnalyzer: any SceneLayerAnalyzing = MockSceneLayerAnalyzer(),
        cameraActivity: any CameraLiveActivityService = MockCameraLiveActivityService()
    ) {
        self.camera = camera
        self.cameraPreview = cameraPreview
        self.cameraActivity = cameraActivity
        self.hardware = hardware
        self.understanding = understanding
        self.story = story
        self.generation = generation
        self.modelCatalog = modelCatalog
        self.modelConfigurationStore = modelConfigurationStore
        self.storage = storage
        self.haptics = haptics
        self.motionField = motionField
        self.captureMotion = captureMotion
        self.sceneLayerAnalyzer = sceneLayerAnalyzer
    }

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
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService(),
            captureMotion: MockCaptureMotionService(),
            sceneLayerAnalyzer: MockSceneLayerAnalyzer()
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
            haptics: MockHapticsClient(),
            motionField: MockMotionFieldService(),
            captureMotion: MockCaptureMotionService(),
            sceneLayerAnalyzer: MockSceneLayerAnalyzer()
        )
    }

    @MainActor
    static var runtime: AppDependencies {
        let baseURL = FUMIRAAPIConfiguration.baseURL
        let generation: any GenerationProvider = baseURL.map { RemoteGenerationProvider(baseURL: $0) } ?? MockGenerationProvider()
        let understanding: any ImageUnderstandingProvider = baseURL.map { RemoteUnderstandingProvider(baseURL: $0) } ?? MockImageUnderstandingProvider()
        let story: any StoryProvider = baseURL.map { RemoteStoryProvider(baseURL: $0) } ?? MockStoryProvider()

        #if targetEnvironment(simulator)
        return AppDependencies(
            camera: MockCameraService(),
            cameraPreview: MockCameraPreviewFactory(),
            hardware: MockHardwareController(),
            understanding: understanding,
            story: story,
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: UserDefaultsAIModelConfigurationStore(),
            storage: PhotoLibraryPosterStorage(),
            haptics: LiveHapticsClient(),
            motionField: MockMotionFieldService(),
            captureMotion: MockCaptureMotionService(),
            sceneLayerAnalyzer: MockSceneLayerAnalyzer(),
            cameraActivity: LiveCameraLiveActivityService()
        )
        #else
        let liveCamera = LiveCameraService()
        return AppDependencies(
            camera: liveCamera,
            cameraPreview: liveCamera,
            hardware: MockHardwareController(),
            understanding: understanding,
            story: story,
            generation: generation,
            modelCatalog: BundledAIModelCatalogProvider(),
            modelConfigurationStore: UserDefaultsAIModelConfigurationStore(),
            storage: PhotoLibraryPosterStorage(),
            haptics: LiveHapticsClient(),
            motionField: CoreMotionFieldService(),
            captureMotion: CoreCaptureMotionService(),
            sceneLayerAnalyzer: VisionSceneLayerAnalyzer(),
            cameraActivity: LiveCameraLiveActivityService()
        )
        #endif
    }
}
