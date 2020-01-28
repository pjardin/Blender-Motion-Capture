//
//  FacialCaptureView.swift
//  Blender Motion Capture
//
//  Created by Pascal Jardin on 1/11/20.
//  Copyright © 2020 Jardin Labs. All rights reserved.
//


import UIKit
import SceneKit
import ARKit
import MessageUI

import AVFoundation

//https://developer.apple.com/documentation/arkit/arfaceanchor/blendshapelocation
var blendShape = [String: [Float] ]()

var headAngles = [[Float]]()

var leftEyeAngles = [[Float]]()
var rightEyeAngles = [[Float]]()



let frameRate = 1.0/24

class FacialCaptureView: UIViewController, UITextFieldDelegate, AVAudioRecorderDelegate, ARSCNViewDelegate, MFMailComposeViewControllerDelegate {

    @IBOutlet weak var faceView: SCNView!
    @IBOutlet var trackingView: ARSCNView!
    
    @IBOutlet var email: UITextField!
    
    @IBOutlet var buttonsRecord: UIButton!
    
    
    var playerItem:AVPlayerItem?
    var player:AVPlayer?
    
    
    var contentNode: SCNReferenceNode? // Reference to the .scn file
    var cameraPosition = SCNVector3Make(0, 15, 50) // Camera node to set position that the SceneKit is looking at the character
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private lazy var model = contentNode!.childNode(withName: "model", recursively: true)! // Whole model including eyes
    private lazy var head = contentNode!.childNode(withName: "head", recursively: true)! // Contains blendshapes

    
    var recording = false
    
    var recordingSession: AVAudioSession!
    var audioRecorder: AVAudioRecorder!
    
    var audioFilename: URL!
    
    override func viewDidLoad() {
        UIApplication.shared.isIdleTimerDisabled = true
        super.viewDidLoad()
         initBlendShapes()
        self.email.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(setUpCap(_:)), name: Notification.Name(rawValue: "setUpCap"), object: nil)

        
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
            if (granted) {
                // If access is granted, setup the main view
                DispatchQueue.main.sync {
                    self.setupFaceTracker()
                    self.sceneSetup()
                    self.createCameraNode()
                }
            } else {
                // If access is not granted, throw error and exit
                fatalError("This app needs Camera Access to function. You can grant access in Settings.")
            }
        }
        
        setUpRecorder()
 
        

        
        
    }
    @objc func setUpCap(_ notification: Notification) {
        initBlendShapes()

        AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
            if (granted) {
                // If access is granted, setup the main view
                DispatchQueue.main.sync {
                    self.setupFaceTracker()
                    self.createCameraNode()
                }
            } else {
                // If access is not granted, throw error and exit
                fatalError("This app needs Camera Access to function. You can grant access in Settings.")
            }
        }
        
        setUpRecorder()

    }
    
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
    func setupFaceTracker() {
        // Configure and start face tracking session
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        
        // Run ARSession and set delegate to self
        self.trackingView.session.run(configuration)
        self.trackingView.delegate = self
        self.trackingView.isHidden = false // Remove if you want to see the camera feed
    }
    
    func sceneSetup() {

        if let filePath = Bundle.main.path(forResource: "Smiley", ofType: "scn") {
            let referenceURL = URL(fileURLWithPath: filePath)
            
            self.contentNode = SCNReferenceNode(url: referenceURL)
            self.contentNode?.load()
            self.head.morpher?.unifiesNormals = true // ensures the normals are not morphed but are recomputed after morphing the vertex instead. Otherwise the node has a low poly look.
            self.scene.rootNode.addChildNode(self.contentNode!)
        }
        self.faceView.autoenablesDefaultLighting = true

        // set the scene to the view
        self.faceView.scene = self.scene
        
        // allows the user to manipulate the camera
        self.faceView.allowsCameraControl = false

        // configure the view
        self.faceView.backgroundColor = .clear
    }
    
    func setUpRecorder(){
        recordingSession = AVAudioSession.sharedInstance()

        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            recordingSession.requestRecordPermission() {_ in }
        } catch {
            // failed to record!
        }
    }
    

    
    func createCameraNode () {
        self.cameraNode.camera = SCNCamera()
        self.cameraNode.position = self.cameraPosition
        self.scene.rootNode.addChildNode(self.cameraNode)
        self.faceView.pointOfView = self.cameraNode
    }
    
    func calculateEulerAngles(_ faceAnchor: ARFaceAnchor) -> SCNVector3 {
        // Based on StackOverflow answer https://stackoverflow.com/a/53434356/3599895
        let projectionMatrix = self.trackingView.session.currentFrame?.camera.projectionMatrix(for: .portrait, viewportSize: self.faceView.bounds.size, zNear: 0.001, zFar: 1000)
        let viewMatrix = self.trackingView.session.currentFrame?.camera.viewMatrix(for: .portrait)
        
        let projectionViewMatrix = simd_mul(projectionMatrix!, viewMatrix!)
        let modelMatrix = faceAnchor.transform
        let mvpMatrix = simd_mul(projectionViewMatrix, modelMatrix)
        
        // This allows me to just get a .x .y .z rotation from the matrix, without having to do crazy calculations
        let newFaceMatrix = SCNMatrix4.init(mvpMatrix)
        let faceNode = SCNNode()
        faceNode.transform = newFaceMatrix
        let rotation = vector_float3(faceNode.worldOrientation.x, faceNode.worldOrientation.y, faceNode.worldOrientation.z)
        let yaw = (rotation.y*3)
        let pitch = (rotation.x*3)
        let roll = (rotation.z*1.5)
        
        return SCNVector3(pitch, yaw, roll)
    }
    
    
    @IBAction func click(_ sender: UIButton) {
        if (recording == false){
            
            let path = Bundle.main.path(forResource: "countDown", ofType:"wav")!
            let url = URL(fileURLWithPath: path)
            
            playerItem = AVPlayerItem(url: url as URL)
            NotificationCenter.default.addObserver(self, selector: #selector(self.playerDidFinishPlaying(sender:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem)

            player=AVPlayer(playerItem: playerItem!)
            player?.volume = 30
            player!.play()
            
            UIView.animate(withDuration: 1, delay: 0.0, options: [.curveEaseInOut, .repeat, .autoreverse, .allowUserInteraction], animations: {() -> Void in
                self.buttonsRecord.alpha = 0.0
                }, completion: {(finished: Bool) -> Void in
            })
            

        } else {
            buttonsRecord.setTitle("record", for: .normal)
            buttonsRecord.backgroundColor = UIColor.green
            recording = false
            finishRecording(success: true)

            sendEmail()
        }
    }
    @objc func playerDidFinishPlaying(sender: Notification) {
        
        self.buttonsRecord.layer.removeAllAnimations()
        self.buttonsRecord.alpha = 1
        
        buttonsRecord.setTitle("stop", for: .normal)
        buttonsRecord.backgroundColor = UIColor.red
        recording = true
        startRecording()
        
    }
    
    
    func sendEmail(){
        print("send Email!!")
        //print(blendShape)
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setSubject("face data")
            mail.setToRecipients([email.text!])
            mail.setMessageBody("<p>drag and drop to the blender addon!</p>", isHTML: true)

            
            //grab audio file
            if let fileData = NSData(contentsOf: audioFilename) {
                print("File data loaded.")
                mail.addAttachmentData(fileData as Data, mimeType: "audio/wav", fileName: "audio")
            }
            
            
            //grab blendshape data
            var JSONdata = try! JSONSerialization.data(withJSONObject: blendShape, options: JSONSerialization.WritingOptions.prettyPrinted)
            
            //https://www.iana.org/assignments/media-types/media-types.xhtml
            mail.addAttachmentData(JSONdata as Data, mimeType: "application/json", fileName: "blendShapes")
            
            //clear blendShape data
            initBlendShapes()
            
            //grab head data
            JSONdata = try! JSONSerialization.data(withJSONObject: headAngles, options: JSONSerialization.WritingOptions.prettyPrinted)
            
            //https://www.iana.org/assignments/media-types/media-types.xhtml
            mail.addAttachmentData(JSONdata as Data, mimeType: "application/json", fileName: "head")
            
            //clear head data
            headAngles = [[Float]]()
            
            
            //grab leftEyeAngles data
            JSONdata = try! JSONSerialization.data(withJSONObject: leftEyeAngles, options: JSONSerialization.WritingOptions.prettyPrinted)
            
            //https://www.iana.org/assignments/media-types/media-types.xhtml
            mail.addAttachmentData(JSONdata as Data, mimeType: "application/json", fileName: "leftEye")
            
            //clear leftEyeAngles data
            leftEyeAngles = [[Float]]()
            
            
            //grab rightEyeAngles data
            JSONdata = try! JSONSerialization.data(withJSONObject: rightEyeAngles, options: JSONSerialization.WritingOptions.prettyPrinted)
            
            //https://www.iana.org/assignments/media-types/media-types.xhtml
            mail.addAttachmentData(JSONdata as Data, mimeType: "application/json", fileName: "rightEye")
            
            //clear rightEyeAngles data
            rightEyeAngles = [[Float]]()
            
            
            present(mail, animated: true)
        } else {
            // show failure alert
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
    
    
    
    
    func startRecording() {
        audioFilename = getDocumentsDirectory().appendingPathComponent("recording.wav")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.record()

        } catch {
            finishRecording(success: false)
        }
    }
    
    func finishRecording(success: Bool) {
        audioRecorder.stop()
        audioRecorder = nil
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    
    var time = CACurrentMediaTime();
    
    //https://developer.apple.com/documentation/arkit/arfaceanchor
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        
        let newTime = CACurrentMediaTime()
        
        let dif = newTime - time
        
        if (  dif >=  frameRate ){

            DispatchQueue.main.async {

                let blendShapes = faceAnchor.blendShapes
                // This will only work correctly if the shape keys are given the exact same name as the blendshape names
                for (key, value) in blendShapes {
                    if let fValue = value as? Float {
                        self.head.morpher?.setWeight(CGFloat(fValue), forTargetNamed: key.rawValue)
                    }
                    if (self.recording == true){
                        blendShape[key.rawValue]?.append(Float(truncating: value))
                    }
                }
                self.model.eulerAngles = self.calculateEulerAngles(faceAnchor)
                
                if (self.recording == true){

                    headAngles.append(faceAnchor.transform.eulerAngles)
                    leftEyeAngles.append(faceAnchor.leftEyeTransform.eulerAngles)
                    rightEyeAngles.append(faceAnchor.rightEyeTransform.eulerAngles)

                }

                
                
            }
            
            time = newTime - (dif - frameRate) //this is to keep it at check.
            
        }
                
        
    }
    
    func initBlendShapes(){
        blendShape = [
             //Left Eye
             "eyeBlink_L"       : [],
             "eyeLookDown_L"    : [],
             "eyeLookIn_L"      : [],
             "eyeLookOut_L"     : [],
             "eyeLookUp_L"      : [],
             "eyeSquint_L"      : [],
             "eyeWide_L"        : [],
             //Right Eye
             "eyeBlink_R"       : [],
             "eyeLookDown_R"    : [],
             "eyeLookIn_R"      : [],
             "eyeLookOut_R"     : [],
             "eyeLookUp_R"      : [],
             "eyeSquint_R"      : [],
             "eyeWide_R"        : [],
             //jaw
             "jawForward"       : [],
             "jawLeft"          : [],
             "jawRight"         : [],
             "jawOpen"          : [],
             //mouth
             "mouthClose"       : [],
             "mouthFunnel"      : [],
             "mouthPucker"      : [],
             "mouthLeft"        : [],
             "mouthRight"       : [],
             "mouthSmile_L"     : [],
             "mouthSmile_R"     : [],
             "mouthFrown_L"     : [],
             "mouthFrown_R"     : [],
             "mouthDimple_L"    : [],
             "mouthDimple_R"    : [],
             "mouthStretch_L"   : [],
             "mouthStretch_R"   : [],
             "mouthRollLower"   : [],
             "mouthRollUpper"   : [],
             "mouthShrugLower"  : [],
             "mouthShrugUpper"  : [],
             "mouthPress_L"     : [],
             "mouthPress_R"     : [],
             "mouthLowerDown_L" : [],
             "mouthLowerDown_R" : [],
             "mouthUpperUp_L"   : [],
             "mouthUpperUp_R"   : [],
             //brow
             "browDown_L"       : [],
             "browDown_R"       : [],
             "browInnerUp"      : [],
             "browOuterUp_L"    : [],
             "browOuterUp_R"    : [],
             //cheek
             "cheekPuff"        : [],
             "cheekSquint_L"    : [],
             "cheekSquint_R"    : [],
             //nose
             "noseSneer_L"      : [],
             "noseSneer_R"      : [],
             //tongue
             "tongueOut"        : []
        ]
    }
    
}



//https://michael-martinez.fr/arkit-transform-matrices-quaternions-and-related-conversions/

public extension matrix_float4x4 {

/// Retrieve translation from a quaternion matrix
    var translation: SCNVector3 {
    get {
        return SCNVector3Make(columns.3.x, columns.3.y, columns.3.z)
    }
}

/// Retrieve euler angles from a quaternion matrix
    var eulerAngles: [Float] {
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

        
        let angles = [pitch,
                      yaw,
                      roll]
        
        return angles
    }
}
}
