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

import ReplayKit

//https://developer.apple.com/documentation/arkit/arfaceanchor/blendshapelocation
var blendShape = [String: [[Int]] ]()

var headAngles = [[Float]]()

var leftEyeAngles = [[Float]]()
var rightEyeAngles = [[Float]]()



let frameRate = 1.0/24

var audioFilename: URL!






class FacialCaptureView: UIViewController, UITextFieldDelegate, AVAudioRecorderDelegate, ARSCNViewDelegate, MFMailComposeViewControllerDelegate, RPPreviewViewControllerDelegate {

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
    
    let recorder = RPScreenRecorder.shared()
    
    var screenRecord = false;
    
    @IBAction func screenSwitch(_ sender: UISwitch) {
    
        if screenRecord == false {
            screenRecord = true

        } else {
            screenRecord = false
        }
        
        print(screenRecord)
    }
    
    
    
    
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
            
            if (screenRecord) {
                recorder.startRecording()
            }
            
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

            stopScreenRecording()

            
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
    
    
    func stopScreenRecording() {
        
        if recorder.isRecording == false {
                        sendEmail()
        }
        
        recorder.stopRecording { [unowned self] (preview, error) in
                       
                       if let unwrappedPreview = preview {
                           unwrappedPreview.previewControllerDelegate = self
                           self.present(unwrappedPreview, animated: true)
                       }
            
        }

    }
    
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        dismiss(animated: true)
        sendEmail()
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
            var JSONdata = try! JSONSerialization.data(withJSONObject: blendShape, options: JSONSerialization.WritingOptions.init())
            
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

    
    var frameCount = 0
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
                        
                        let v =  Int(round( Float(truncating: value) * 100) ) //   /100;

                        if (key.rawValue == "eyeSquint_L" ){
                            blendShape["Bone.055"]!.append([v])
                        }
                        else if (key.rawValue == "eyeSquint_R" ){
                            blendShape["Bone.056"]!.append([v])
                        }
                        else if (key.rawValue == "mouthClose" ){
                            blendShape["Bone.054"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthFunnel" ){
                            blendShape["Bone.053"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthPucker" ){
                            blendShape["Bone.052"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthLowerDown_L" ){
                            blendShape["Bone.037"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthLowerDown_R" ){
                            blendShape["Bone.036"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthUpperUp_L" ){
                            blendShape["Bone.044"]!.append([v])
                        }
                        else if (key.rawValue == "mouthUpperUp_R" ){
                            blendShape["Bone.045"]!.append([v])
                        }
                        else if (key.rawValue == "browDown_L" ){
                            blendShape["Bone.062"]!.append([-v])
                        }
                        else if (key.rawValue == "browDown_R" ){
                            blendShape["Bone.064"]!.append([-v])
                        }
                        else if (key.rawValue == "browInnerUp" ){
                            blendShape["Bone.063"]!.append([v])
                        }
                        else if (key.rawValue == "browOuterUp_L" ){
                            blendShape["Bone.061"]!.append([v])
                        }
                        else if (key.rawValue == "browOuterUp_R" ){
                            blendShape["Bone.065"]!.append([v])
                        }
                        else if (key.rawValue == "cheekPuff" ){
                            blendShape["Bone.050"]!.append([-v])
                        }
                        else if (key.rawValue == "cheekSquint_L" ){
                            blendShape["Bone.046"]!.append([v])
                        }
                        else if (key.rawValue == "cheekSquint_R" ){
                            blendShape["Bone.049"]!.append([v])
                        }
                        else if (key.rawValue == "noseSneer_L" ){
                            blendShape["Bone.047"]!.append([v])
                        }
                        else if (key.rawValue == "noseSneer_R" ){
                            blendShape["Bone.048"]!.append([v])
                        }
                        else if (key.rawValue == "tongueOut" ){
                            blendShape["Bone.051"]!.append([-v])
                        }
                        //------------------------------------
                        else if (key.rawValue == "eyeBlink_L" ){
                            if (blendShape["Bone.059"]!.count != self.frameCount + 1){
                                blendShape["Bone.059"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.059"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "eyeWide_L" ){

                            if (blendShape["Bone.059"]!.count != self.frameCount + 1){
                                blendShape["Bone.059"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.059"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "eyeBlink_R" ){
                            if (blendShape["Bone.060"]!.count != self.frameCount + 1){
                                blendShape["Bone.060"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.060"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "eyeWide_R" ){
                            if (blendShape["Bone.060"]!.count != self.frameCount + 1){
                                blendShape["Bone.060"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.060"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "mouthLeft" ){
                            if (blendShape["Bone.040"]!.count != self.frameCount + 1){
                                blendShape["Bone.040"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.040"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "mouthRight" ){
                            if (blendShape["Bone.040"]!.count != self.frameCount + 1){
                                blendShape["Bone.040"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.040"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "mouthStretch_L" ){
                            if (blendShape["Bone.038"]!.count != self.frameCount + 1){
                                blendShape["Bone.038"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.038"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "mouthPress_L" ){
                            if (blendShape["Bone.038"]!.count != self.frameCount + 1){
                                blendShape["Bone.038"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.038"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "mouthStretch_R" ){
                            if (blendShape["Bone.042"]!.count != self.frameCount + 1){
                                blendShape["Bone.042"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.042"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "mouthPress_R" ){
                            if (blendShape["Bone.042"]!.count != self.frameCount + 1){
                                blendShape["Bone.042"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.042"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "mouthRollLower" ){
                            if (blendShape["Bone.035"]!.count != self.frameCount + 1){
                                blendShape["Bone.035"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.035"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "mouthRollUpper" ){
                            if (blendShape["Bone.035"]!.count != self.frameCount + 1){
                                blendShape["Bone.035"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.035"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "mouthShrugLower" ){
                            if (blendShape["Bone.043"]!.count != self.frameCount + 1){
                                blendShape["Bone.043"]!.append([-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.043"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "mouthShrugUpper" ){
                            if (blendShape["Bone.043"]!.count != self.frameCount + 1){
                                blendShape["Bone.043"]!.append([v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.043"]?[self.frameCount][0] += v
                            }
                        }
                        
                        //======================================
                            
                        else if (key.rawValue == "eyeLookDown_L" ){
                            if (blendShape["Bone.057"]!.count != self.frameCount + 1){
                                blendShape["Bone.057"]!.append([0, -v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.057"]?[self.frameCount][1] += -v
                            }
                        }
                        else if (key.rawValue == "eyeLookIn_L" ){
                            if (blendShape["Bone.057"]!.count != self.frameCount + 1){
                                blendShape["Bone.057"]!.append([v, 0])
                            }
                            else if ( v != 0){
                                blendShape["Bone.057"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "eyeLookOut_L" ){
                            if (blendShape["Bone.057"]!.count != self.frameCount + 1){
                                blendShape["Bone.057"]!.append([-v, 0])
                            }
                            else if ( v != 0){
                                blendShape["Bone.057"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "eyeLookUp_L" ){
                            if (blendShape["Bone.057"]!.count != self.frameCount + 1){
                                blendShape["Bone.057"]!.append([0, v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.057"]?[self.frameCount][1] += v
                            }
                        }
                        //-------------------------------------
                        else if (key.rawValue == "eyeLookDown_R" ){
                            
                            if (blendShape["Bone.058"]!.count != self.frameCount + 1){
                                blendShape["Bone.058"]!.append([0,-v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.058"]?[self.frameCount][1] += -v
                            }
                        }
                        else if (key.rawValue == "eyeLookIn_R" ){
                            if (blendShape["Bone.058"]!.count != self.frameCount + 1){
                                blendShape["Bone.058"]!.append([-v, 0])
                            }
                            else if ( v != 0){
                                blendShape["Bone.058"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "eyeLookOut_R" ){
                            if (blendShape["Bone.058"]!.count != self.frameCount + 1){
                                blendShape["Bone.058"]!.append([v, 0])
                            }
                            else if ( v != 0){
                                blendShape["Bone.058"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "eyeLookUp_R" ){
                            if (blendShape["Bone.058"]!.count != self.frameCount + 1){
                                blendShape["Bone.058"]!.append([0,v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.058"]?[self.frameCount][1] += v
                            }
                        }
                        //-------------------------------------
                        else if (key.rawValue == "jawForward" ){
                            if (blendShape["Bone.034"]!.count != self.frameCount + 1){
                                blendShape["Bone.034"]!.append( [0, v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.034"]?[self.frameCount][1] += v
                            }
                        }
                        else if (key.rawValue == "jawLeft" ){
                            if (blendShape["Bone.034"]!.count != self.frameCount + 1){
                                blendShape["Bone.034"]!.append([-v, 0])
                            }
                            else if ( v != 0){
                                blendShape["Bone.034"]?[self.frameCount][0] += -v
                            }
                        }
                        else if (key.rawValue == "jawRight" ){
                            if (blendShape["Bone.034"]!.count != self.frameCount + 1){
                                blendShape["Bone.034"]!.append([v, 0])
                            }
                            else if ( v != 0){
                                blendShape["Bone.034"]?[self.frameCount][0] += v
                            }
                        }
                        else if (key.rawValue == "jawOpen" ){
                            if (blendShape["Bone.034"]!.count != self.frameCount + 1){
                                blendShape["Bone.034"]!.append([0, -v])
                            }
                            else if ( v != 0){
                                blendShape["Bone.034"]?[self.frameCount][1] += -v
                            }
                        }
                        //-------------------------------------
                        else if (key.rawValue == "mouthSmile_L" ){
                            blendShape["Bone.068"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthFrown_L" ){
                            blendShape["Bone.070"]!.append([-v])
                        }
                        else if (key.rawValue == "mouthDimple_L" ){
                            blendShape["Bone.039"]!.append([-v])
                        }
                            
                        //-------------------------------------
                        else if (key.rawValue == "mouthSmile_R" ){
                            blendShape["Bone.072"]!.append([v])
                        }
                        else if (key.rawValue == "mouthFrown_R" ){
                            blendShape["Bone.074"]!.append([v])
                        }
                        else if (key.rawValue == "mouthDimple_R" ){
                            blendShape["Bone.041"]!.append([v])
                        }
                        //-------------------------------------
                        
                       
                    }
                }
                
                
                self.model.eulerAngles = self.calculateEulerAngles(faceAnchor)
                
                if (self.recording == true){

                    headAngles.append(faceAnchor.transform.eulerAngles)
                    leftEyeAngles.append(faceAnchor.leftEyeTransform.eulerAngles)
                    rightEyeAngles.append(faceAnchor.rightEyeTransform.eulerAngles)
                    
                    self.frameCount += 1

                }

                
                
            }
            
            time = newTime - (dif - frameRate) //this is to keep it at check.
            
        }
                
        
    }
    
    func initBlendShapes(){
        frameCount = 0;
        
        blendShape = ["Bone.059" : [],
        "Bone.057" : [],
        "Bone.055" : [],
        "Bone.060" : [],
        "Bone.058" : [],
        "Bone.056" : [],
        "Bone.034" : [],
        "Bone.054" : [],
        "Bone.053" : [],
        "Bone.052" : [],
        "Bone.040" : [],
        "Bone.039" : [],
        "Bone.041" : [],
        "Bone.038" : [],
        "Bone.042" : [],
        "Bone.035" : [],
        "Bone.043" : [],
        "Bone.037" : [],
        "Bone.036" : [],
        "Bone.044" : [],
        "Bone.045" : [],
        "Bone.062" : [],
        "Bone.064" : [],
        "Bone.063" : [],
        "Bone.061" : [],
        "Bone.065" : [],
        "Bone.050" : [],
        "Bone.046" : [],
        "Bone.049" : [],
        "Bone.047" : [],
        "Bone.048" : [],
        "Bone.051" : [], //
        "Bone.072" : [],
        "Bone.074" : [],
        "Bone.068" : [],
        "Bone.070" : [] ]
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
