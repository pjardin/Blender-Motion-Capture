//
//  MotionCaptureView .swift
//  Blender Motion Capture
//
//  Created by Pascal Jardin on 1/27/20.
//  Copyright © 2020 Jardin Labs. All rights reserved.
//

import Foundation
import AVFoundation

import UIKit
import RealityKit
import ARKit
import Combine


var motcap = [String: [[Float]] ]()

//let frameRate = 1.0/24


class MotionCaptureView: UIViewController, ARSessionDelegate {

    @IBOutlet var arView: ARView!
    
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // [-1.0, 0, 0]Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
    override func viewDidAppear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = true
        super.viewDidAppear(animated)
        arView.session.delegate = self
        
        guard let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: .video, position: .front) else {
            return
        }
        
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)
        
        arView.scene.addAnchor(characterAnchor)
        
        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                // Scale the character to human size
                character.scale = [1.0, 1.0, 1.0]
                self.character = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
        
        initBlendShapes();
    }
    
    func initBlendShapes(){
        motcap = [
        "head"           : [],
        
        "leftFoot"       : [],
        "leftHand"       : [],
        "leftSholder"    : [],
        
        "rightFoot"      : [],
        "rightHand"      : [],
        "rightSholder"   : [],
        
        "root"           : []
        ]

        
    }
    
    
    var time = CACurrentMediaTime();
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
            
            // Update the position of the character anchor's position.
            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            characterAnchor.position = bodyPosition + characterOffset
            // Also copy over the rotation of the body anchor, because the skeleton's pose
            // in the world is relative to the body anchor's rotation.
            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
            
            
            let newTime = CACurrentMediaTime()
            
            let dif = newTime - time
            
            if (  dif >=  frameRate ){
            
                let skeleton = bodyAnchor.skeleton

                //https://developer.apple.com/documentation/arkit/arskeletonjointnamehead?language=objc
                let head = skeleton.localTransform(for: ARSkeleton.JointName.head)
                
                let leftFoot = skeleton.localTransform(for: ARSkeleton.JointName.leftFoot)
                let leftHand = skeleton.localTransform(for: ARSkeleton.JointName.leftHand)
                let leftSholder = skeleton.localTransform(for: ARSkeleton.JointName.leftShoulder)

                let rightFoot = skeleton.localTransform(for: ARSkeleton.JointName.rightFoot)
                let rightHand = skeleton.localTransform(for: ARSkeleton.JointName.rightHand)
                let rightSholder = skeleton.localTransform(for: ARSkeleton.JointName.rightShoulder)

                let root = skeleton.localTransform(for: ARSkeleton.JointName.root)

                
                motcap["head"]?.append(head!.pos_eulerAngles)
                
                motcap["leftFoot"]?.append(leftFoot!.pos_eulerAngles)
                motcap["leftHand"]?.append(leftHand!.pos_eulerAngles)
                motcap["leftSholder"]?.append(leftSholder!.pos_eulerAngles)

                motcap["rightFoot"]?.append(rightFoot!.pos_eulerAngles)
                motcap["rightHand"]?.append(rightHand!.pos_eulerAngles)
                motcap["rightSholder"]?.append(rightSholder!.pos_eulerAngles)

                motcap["root"]?.append(root!.pos_eulerAngles)
                
                
                time = newTime - (dif - frameRate) //this is to keep it at check.
                
            }
            
            if let character = character, character.parent == nil {
                // Attach the character to its anchor as soon as
                // 1. the body anchor was detected and
                // 2. the character was loaded.
                characterAnchor.addChild(character)
            }
        }
    }
    
    @IBAction func Back(_ sender: UIButton) {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "setUpCap"), object: nil)

        self.dismiss(animated: true, completion: nil)
    }
    
    
}






//https://michael-martinez.fr/arkit-transform-matrices-quaternions-and-related-conversions/
public extension matrix_float4x4 {


        //return [x, y, z, pitch, yaw, roll]
        var pos_eulerAngles: [Float] {
        get {
            //first we get the quaternion from m00...m22
            //see http://www.euclideanspace.com/maths/geometry/rotations/conversions/matrixToQuaternion/index.htm
            let qw = sqrt(1 + self.columns.0.x + self.columns.1.y + self.columns.2.z) / 2.0
            let qx = (self.columns.2.y - self.columns.1.z) / (qw * 4.0)
            let qy = (self.columns.0.z - self.columns.2.x) / (qw * 4.0)
            let qz = (self.columns.1.x - self.columns.0.y) / (qw * 4.0)

            //then we deduce euler angles with some cosines
            //see https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles
            // roll (x-axis rotation)
            let sinr = +2.0 * (qw * qx + qy * qz)
            let cosr = +1.0 - 2.0 * (qx * qx + qy * qy)
            let roll = atan2(sinr, cosr)

            // pitch (y-axis rotation)
            let sinp = +2.0 * (qw * qy - qz * qx)
            var pitch: Float
            if abs(sinp) >= 1 {
                 pitch = copysign(Float.pi / 2, sinp)
            } else {
                pitch = asin(sinp)
            }

            // yaw (z-axis rotation)
            let siny = +2.0 * (qw * qz + qx * qy)
            let cosy = +1.0 - 2.0 * (qy * qy + qz * qz)
            let yaw = atan2(siny, cosy)

            //https://stackoverflow.com/questions/45212598/convert-matrix-float4x4-to-x-y-z-space
            return [columns.3.x, columns.3.y, columns.3.z, pitch, yaw, roll]
        }
    }
    
}


