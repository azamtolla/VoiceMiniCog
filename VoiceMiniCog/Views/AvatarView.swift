//
//  AvatarView.swift
//  VoiceMiniCog
//

import SwiftUI
import SceneKit
import QuartzCore

struct AvatarView: UIViewRepresentable {
    let blendshapes: [String: Float]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor.systemGray6
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = true
        scnView.scene = context.coordinator.makeScene()
        context.coordinator.attach(to: scnView)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.latestBlendshapes = blendshapes
    }

    final class Coordinator {
        private weak var scnView: SCNView?
        private var displayLink: CADisplayLink?
        var latestBlendshapes: [String: Float] = [:]
        private var morpher: SCNMorpher?
        private var targetIndexByName: [String: Int] = [:]
        private var warnedMissingTargets: Set<String> = []

        // 52 ARKit-style blendshape keys
        private let arkitKeys: [String] = [
            "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
            "cheekPuff", "cheekSquintLeft", "cheekSquintRight",
            "eyeBlinkLeft", "eyeBlinkRight", "eyeLookDownLeft", "eyeLookDownRight",
            "eyeLookInLeft", "eyeLookInRight", "eyeLookOutLeft", "eyeLookOutRight",
            "eyeLookUpLeft", "eyeLookUpRight", "eyeSquintLeft", "eyeSquintRight",
            "eyeWideLeft", "eyeWideRight", "jawForward", "jawLeft", "jawOpen", "jawRight",
            "mouthClose", "mouthDimpleLeft", "mouthDimpleRight", "mouthFrownLeft", "mouthFrownRight",
            "mouthFunnel", "mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthPressLeft",
            "mouthPressRight", "mouthPucker", "mouthRight", "mouthRollLower", "mouthRollUpper",
            "mouthShrugLower", "mouthShrugUpper", "mouthSmileLeft", "mouthSmileRight",
            "mouthStretchLeft", "mouthStretchRight", "mouthUpperUpLeft", "mouthUpperUpRight",
            "noseSneerLeft", "noseSneerRight", "tongueOut"
        ]

        func attach(to scnView: SCNView) {
            self.scnView = scnView
            setupMorpherIfPossible(in: scnView.scene)
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func makeScene() -> SCNScene {
            if let scene = loadAvatarScene() {
                return scene
            }
            return makeFallbackScene()
        }

        private func loadAvatarScene() -> SCNScene? {
            if let directURL = Bundle.main.url(forResource: "avatar_head", withExtension: "usdz"),
               let scene = try? SCNScene(url: directURL, options: nil) {
                return scene
            }
            if let firstUSDZ = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil)?.first,
               let scene = try? SCNScene(url: firstUSDZ, options: nil) {
                return scene
            }
            return nil
        }

        private func makeFallbackScene() -> SCNScene {
            let scene = SCNScene()

            let sphere = SCNSphere(radius: 1.0)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemTeal
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(node)

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 0, 4.2)
            scene.rootNode.addChildNode(cameraNode)

            return scene
        }

        private func setupMorpherIfPossible(in scene: SCNScene?) {
            guard let scene else { return }
            guard let faceNode = findFirstMorpherNode(in: scene.rootNode),
                  let morpher = faceNode.morpher else {
                return
            }

            self.morpher = morpher
            targetIndexByName = [:]
            for (idx, target) in morpher.targets.enumerated() {
                if let geo = target as? SCNGeometry, let name = geo.name?.lowercased() {
                    targetIndexByName[name] = idx
                }
            }
        }

        private func findFirstMorpherNode(in node: SCNNode) -> SCNNode? {
            if node.morpher != nil { return node }
            for child in node.childNodes {
                if let found = findFirstMorpherNode(in: child) {
                    return found
                }
            }
            return nil
        }

        @objc private func tick() {
            guard let morpher else { return }
            for key in arkitKeys {
                let normalized = clamp01(latestBlendshapes[key] ?? 0)
                apply(weight: normalized, for: key, to: morpher)
            }
        }

        private func apply(weight: Float, for key: String, to morpher: SCNMorpher) {
            let candidates = [key, key.lowercased(), key.replacingOccurrences(of: "Left", with: "L"), key.replacingOccurrences(of: "Right", with: "R")]
            for candidate in candidates {
                if let idx = targetIndexByName[candidate.lowercased()] {
                    morpher.setWeight(CGFloat(weight), forTargetAt: idx)
                    return
                }
            }

            if !warnedMissingTargets.contains(key) {
                warnedMissingTargets.insert(key)
                print("[AvatarView] Missing morpher target for key: \(key)")
            }
        }

        private func clamp01(_ value: Float) -> Float {
            min(max(value, 0), 1)
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
