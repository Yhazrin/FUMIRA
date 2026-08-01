import Foundation
import Testing
@testable import FUMIRA

struct PixelSequenceTests {
    @Test
    func decodesMultiClipManifest() throws {
        let data = Data(
            """
            {
              "version": 2,
              "frameSize": { "width": 384, "height": 384 },
              "sequences": [
                {
                  "id": "camera",
                  "displayName": "Camera",
                  "playbackMode": "oneShot",
                  "baseClipID": null,
                  "actionProbability": 0.0,
                  "minimumBaseLoops": 0,
                  "reduceMotionClipID": "shoot",
                  "reduceMotionFrameIndex": 1,
                  "clips": [
                    {
                      "id": "calm",
                      "kind": "linear",
                      "frameDurationMilliseconds": 180,
                      "weight": 1.0,
                      "frames": ["calm_00.png", "calm_01.png"]
                    },
                    {
                      "id": "shoot",
                      "kind": "linear",
                      "frameDurationMilliseconds": 115,
                      "weight": 1.0,
                      "frames": ["shoot_00.png", "shoot_01.png"]
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        let library = try PixelSequenceLibrary.decode(data)
        let sequence = try #require(library.sequence(id: "camera"))

        #expect(library.version == 2)
        #expect(library.frameSize == PixelSequenceSize(width: 384, height: 384))
        #expect(sequence.totalSourceFrames == 4)
        #expect(sequence.reduceMotionFrame == "shoot_01.png")
    }

    @Test
    func randomActionWaitsForMinimumBaseLoops() {
        #expect(
            !PixelSequencePlayback.shouldInsertAction(
                probability: 1,
                completedBaseLoops: 1,
                minimumBaseLoops: 2,
                randomUnit: 0
            )
        )
        #expect(
            PixelSequencePlayback.shouldInsertAction(
                probability: 0.4,
                completedBaseLoops: 2,
                minimumBaseLoops: 2,
                randomUnit: 0.2
            )
        )
        #expect(
            !PixelSequencePlayback.shouldInsertAction(
                probability: 0.4,
                completedBaseLoops: 2,
                minimumBaseLoops: 2,
                randomUnit: 0.8
            )
        )
    }

    @Test
    func weightedActionUsesConfiguredWeights() throws {
        let first = makeClip(id: "first", kind: .action, weight: 1)
        let second = makeClip(id: "second", kind: .action, weight: 3)

        let low = try #require(
            PixelSequencePlayback.weightedAction(
                from: [first, second],
                randomUnit: 0.1
            )
        )
        let high = try #require(
            PixelSequencePlayback.weightedAction(
                from: [first, second],
                randomUnit: 0.9
            )
        )

        #expect(low.id == "first")
        #expect(high.id == "second")
    }

    @Test
    func reduceMotionFrameIsClamped() {
        let clip = PixelSequenceClip(
            id: "shoot",
            kind: .linear,
            frameDurationMilliseconds: 115,
            weight: 1,
            frames: ["0.png", "1.png", "2.png"]
        )
        let sequence = PixelSequence(
            id: "camera",
            displayName: "Camera",
            playbackMode: .oneShot,
            baseClipID: nil,
            actionProbability: 0,
            minimumBaseLoops: 0,
            reduceMotionClipID: "shoot",
            reduceMotionFrameIndex: 99,
            clips: [clip]
        )

        #expect(sequence.reduceMotionFrame == "2.png")
    }

    @Test
    func generatedSequencesAreBundledWithEveryFrame() throws {
        let library = try PixelSequenceLibrary.bundled()

        #expect(library.version == 2)
        #expect(library.sequences.map(\.id) == [
            "inspiration-camera",
            "time-machine-travel",
        ])
        #expect(library.sequence(id: "inspiration-camera")?.totalSourceFrames == 24)
        #expect(library.sequence(id: "time-machine-travel")?.totalSourceFrames == 30)

        let frames = library.sequences
            .flatMap(\.clips)
            .flatMap(\.frames)
        #expect(frames.count == 54)

        for frame in frames {
            let resource = frame as NSString
            #expect(
                Bundle.main.url(
                    forResource: resource.deletingPathExtension,
                    withExtension: resource.pathExtension
                ) != nil
            )
        }
    }

    private func makeClip(
        id: String,
        kind: PixelSequenceClipKind,
        weight: Double
    ) -> PixelSequenceClip {
        PixelSequenceClip(
            id: id,
            kind: kind,
            frameDurationMilliseconds: 120,
            weight: weight,
            frames: ["0.png"]
        )
    }
}
