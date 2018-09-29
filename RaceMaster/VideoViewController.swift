// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018 赛道控. All rights reserved.

import UIKit
import AVFoundation
import CoreLocation

import CoreMotion


extension UIView {
    public func slideUp(_ duration:CFTimeInterval) {
        let animation:CATransition = CATransition()
        animation.timingFunction = CAMediaTimingFunction(name:
            CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType.push
        animation.subtype = CATransitionSubtype.fromTop
        animation.duration = duration
        layer.add(animation, forKey: CATransitionType.push.rawValue)
    }
    
    public func slideDown(_ duration:CFTimeInterval) {
        let animation:CATransition = CATransition()
        animation.timingFunction = CAMediaTimingFunction(name:
            CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType.push
        animation.subtype = CATransitionSubtype.fromBottom
        animation.duration = duration
        layer.add(animation, forKey: CATransitionType.push.rawValue)
    }
    
    public func pin(to view: UIView) {
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    public func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            self.layer.render(in: rendererContext.cgContext)
        }
    }
}

class VideoViewController: UIViewController
{
    private var statsViewSnapshot: UIImage!
    
    // MARK: - Video related controls
    private var isRecordingStarted = false
    
    private var captureSession: AVCaptureSession!
    private lazy var videoDataOutput = AVCaptureVideoDataOutput()
    private lazy var audioDataOutput = AVCaptureAudioDataOutput()
    
    var videoWriter: AVAssetWriter!
    var videoWriterInput: AVAssetWriterInput!
    var audioWriterInput: AVAssetWriterInput!
    var sessionAtSourceTime: CMTime?
    
    fileprivate var videoWriterInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    fileprivate lazy var sDeviceRgbColorSpace = CGColorSpaceCreateDeviceRGB()
    fileprivate lazy var bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
    
    private lazy var tmpContext = CIContext(options: nil)
    
    private let videoPath: URL = {
        // set up output file name
        let documentDirectories = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = documentDirectories.first!
        let uniqueName = UUID().uuidString + ".mp4"
        let videoPath = documentDirectory.appendingPathComponent(uniqueName)
        
        // remove file with the same name
        try? FileManager.default.removeItem(at: videoPath)
        return videoPath
    } ()
    
    // MARK: Device Orientation
    override var shouldAutorotate: Bool
    {
        return false
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask
    {
        return .landscapeLeft
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation
    {
        return .landscapeLeft
    }
    
    private let labelColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.5)
    private let labelColorBgBlue = UIColor(red: 45.0/255.0, green: 158.0/255.0, blue: 255.0/255.0, alpha: 0.8)
    
    private var videoPreviewView: VideoPreviewView!
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private var videoFrameRect: CGRect!
    
    private lazy var returnButton: UIButton = {
        let origin = CGPoint(x: 50, y: 50)
        let size = CGSize(width: 50, height: 50)
        let button = createControlButton(origin: origin, size: size, backgroundImage: "return")
        button.addTarget(self, action: #selector(VideoViewController.returnToPreviousView), for: .touchUpInside)
        return button
    }()
    private var videoStartButton: UIButton!
    private var videoStopButton: UIButton!
    
    private var videoTimerMinutes: Int = 0
    private var videoTimerSeconds: Int = 0
    private var videoTimerDisplay: UILabel!
    
    @IBOutlet var statsView: UIView!
    
    private var locationManager: CLLocationManager!
    private var lastLocation: CLLocation? = nil
    @IBOutlet var longitudeContainer: UILabel!
    @IBOutlet var latitudeContainer: UILabel!
    
    //MARK: - Gravity related variables
    @IBOutlet var gravityContainer: Circle!
    @IBOutlet var gravityCrossHair: UIImageView!
    private let gravityContainerWidth = 100.0
    private let gravityContainerHeight = 100.0
    private var gravityCrossHairYConstraint: NSLayoutConstraint? = nil
    private var gravityCrossHairXConstraint: NSLayoutConstraint? = nil
    @IBOutlet var gValueLabel: UILabel!
    

    // MARK: - Speed related controls
    @IBOutlet var hundredsDigitLabel: UILabel!
    @IBOutlet var tensDigitLabel: UILabel!
    @IBOutlet var onesDigitLabel: UILabel!
    private var lastHundredsDigit = 0
    private var lastTensDigit = 0
    private var lastOnesDigit = 0
    private lazy var screenWidth = {
        return UIScreen.main.bounds.width
    }()
    private lazy var screenHeight = {
        return UIScreen.main.bounds.height
    }()
    
    @IBOutlet var accelerateIndicator: UIImageView!
    @IBOutlet var decelerateIndicator: UIImageView!
    
    @IBOutlet var throttleIndicator: UIImageView!
    @IBOutlet var brakeIndicator: UIImageView!
    private lazy var throttleActive = false
    private lazy var brakeActive = false
    private lazy var brakeAmber = false
    
    private lazy var cmManager = CMMotionManager()
    private var currentSpeed: Double = 0
    private var lastSpeed: Double = 0
    private var lastComparedSpeed: Int = 0
    private var lastTimestamp: Date = Date()
    private var lastAcceleration: Double = 0.0
    private var speedLock = false
    private let speedDisplayRefreshInterval: Double = 1 / 5
    private let deviceMotionRefreshInterval: Double = 1 / 30
    private let videoSnapShotFrameRate: Double = 60
    private lazy var accelerationTimelines = [(date: Date, acceleration: Double)]()
    
    private weak var timer: Timer!
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        return formatter
    } ()

    
    // MARK: - Set up capture session
    
    private func setupCaptureSession()
    {
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        let videoDevice = getVideoDevice()
        
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                captureSession.canAddInput(videoDeviceInput)
            else {
                return
            }
        captureSession.addInput(videoDeviceInput)
        
        if let audioDevice = getMicrophone(), let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice), captureSession.canAddInput(audioDeviceInput) {
            captureSession.addInput(audioDeviceInput)
        }
        
        guard captureSession.canAddOutput(videoDataOutput) else { return }
    
        captureSession.sessionPreset = .high
        
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        let queue = DispatchQueue(label: "com.racemaster.queue.record-video.data-output")
        videoDataOutput.setSampleBufferDelegate(self, queue: queue)
        
        let connection = videoDataOutput.connection(with: .video)

        connection?.videoOrientation = .landscapeLeft
        
        //add video output to session
        captureSession.addOutput(videoDataOutput)
        
        //add audio output to session
        if captureSession.canAddOutput(audioDataOutput) {
            audioDataOutput.setSampleBufferDelegate(self, queue: queue)
            captureSession.addOutput(audioDataOutput)
        }
        
        captureSession.commitConfiguration()
        
        self.captureSession = captureSession
    }
    
    private func getVideoDevice() -> AVCaptureDevice
    {
        if let device = AVCaptureDevice.default(.builtInDualCamera,
                                                for: .video, position: .back) {
            return device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video, position: .back) {
            return device
        } else {
            fatalError("Missing expected back camera device.")
        }
    }
    
    private func getMicrophone() -> AVCaptureDevice?
    {
        if let device = AVCaptureDevice.default(.builtInMicrophone, for: .video, position: .back) {
            return device
        }
        return nil
    }
    
    private func testAuthorizedToUseCamera()
    {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            return
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    return
                }
                else {
                    fatalError("User denied use of camera")
                }
            }
        case .denied: // The user has previously denied access.
            fatalError("User denied use of camera")
        case .restricted: // The user can't grant access due to restrictions.
            fatalError("User denied use of camera")
        }
    }
    
    func getAssetWriter() -> AVAssetWriter?
    {
        do {
            videoWriter = try AVAssetWriter(url: videoPath, fileType: AVFileType.mp4)
            
            let videoWidth = UIScreen.main.bounds.width
//            let videoHeight = ceil(videoWidth * 9.0 / 16.0) + 3
            let videoHeight = UIScreen.main.bounds.height
            //Add video input 16:9
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2048000,
//                    AVVideoMaxKeyFrameIntervalKey: 1.0,
                    AVVideoExpectedSourceFrameRateKey: NSNumber(value: 60),
//                    AVVideoQualityKey: NSNumber(value: 1.0),
                ],
                
            ])
            videoWriterInput.expectsMediaDataInRealTime = true //Make sure we are exporting data at realtime
            
            
            if videoWriter.canAdd(videoWriterInput) {
                videoWriter.add(videoWriterInput)
            }
            
            //Add audio input
            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 64000,
                ])
            audioWriterInput.expectsMediaDataInRealTime = true
            if videoWriter.canAdd(audioWriterInput) {
                videoWriter.add(audioWriterInput)
            }
            
            videoWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight,
                kCVPixelFormatOpenGLESCompatibility as String: true,
                ])
            
            return videoWriter
        }
        catch let error {
            fatalError(error.localizedDescription)
        }
    }
    
    // MARK: -
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer.frame = self.view.layer.bounds
    }
    
    override func viewDidLoad() {
        
        testAuthorizedToUseCamera()
        
        self.setupCaptureSession()
        
        super.viewDidLoad()
        
        
        // force landscape before setting up video preview
        let orientation = UIInterfaceOrientation.landscapeLeft.rawValue
        UIDevice.current.setValue(orientation, forKey: "orientation")
        
        //create video preview layer so we can see real timing video frames
        videoPreviewView = createPreview()
        videoPreviewLayer = videoPreviewView.videoPreviewLayer
        videoFrameRect = videoPreviewLayer.bounds

        createStatsViews()
        
        //take snapshots of statsview at 60 fps
        Timer.scheduledTimer(withTimeInterval: 1 / videoSnapShotFrameRate, repeats: true) { (Timer) in
            self.statsViewSnapshot = self.statsView.asImage()
        }
        
        //update speed with interval of speedDisplayRefreshInterval
        Timer.scheduledTimer(withTimeInterval: speedDisplayRefreshInterval, repeats: true, block: { Timer in
            let current = Int(round(self.currentSpeed))
            if current > self.lastComparedSpeed {
                UIView.animate(withDuration: self.speedDisplayRefreshInterval, animations: {
                    self.accelerateIndicator.alpha = 1.0
                    self.decelerateIndicator.alpha = 0.3
                })
            }
            else if current < self.lastComparedSpeed {
                UIView.animate(withDuration: self.speedDisplayRefreshInterval, animations: {
                    self.accelerateIndicator.alpha = 0.3
                    self.decelerateIndicator.alpha = 1.0
                })
            }
            else {
                UIView.animate(withDuration: self.speedDisplayRefreshInterval, animations: {
                    self.accelerateIndicator.alpha = 0.3
                    self.decelerateIndicator.alpha = 0.3
                })
            }
            
            //update speed reading
            self.updateSpeedLabels()
            self.lastComparedSpeed = current
        })
        
        // start data flow to show preview
        self.captureSession.startRunning()
        print("start running session")
    }
    
    @objc public func startVideoRecording()
    {
        print("Recording started...")
        
        // remove start button
        videoStartButton.removeFromSuperview()
        
        // add stop button
        view.addSubview(videoStopButton)
        videoStopButton.addTarget(self, action: #selector(VideoViewController.stopVideoRecording), for: .touchUpInside)
        
        // add timer display and start timing
        view.addSubview(videoTimerDisplay)
        timer = startTimer()
        
        // start getting data
        if let writer = getAssetWriter() {
            
            videoWriter = writer
            
//            let recordingClock = self.captureSession.masterClock!
//            videoWriter.startSession(atSourceTime: CMClockGetTime(recordingClock))
            videoWriter.startWriting()
            
            print("Start recording...")
            isRecordingStarted = true
        }
    }
    
    @objc public func stopVideoRecording()
    {
        guard isRecordingStarted else {
            return
        }
        print("Stopping recording...")

        isRecordingStarted = false
        
        timer.invalidate()
        videoStopButton.removeFromSuperview()
        videoTimerDisplay.removeFromSuperview()
        
        view.addSubview(videoStartButton)
        
        if let writer = videoWriter {
            writer.finishWriting {
                print("Recording finished")
                self.sessionAtSourceTime = nil
                UISaveVideoAtPathToSavedPhotosAlbum(writer.outputURL.path, nil, nil, nil)
            }
        }
    }
    
    @objc private func returnToPreviousView()
    {
        if let nav = self.navigationController {
            nav.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    
    public func createPreview() -> VideoPreviewView
    {
        // create base frame to show video preview
        let videoPreviewView = VideoPreviewView()
        view.addSubview(videoPreviewView)
        let videoPreviewLayer = videoPreviewView.videoPreviewLayer
        videoPreviewLayer.frame = view.bounds
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewView.backgroundColor = UIColor.blue
        videoPreviewLayer.session = captureSession
        videoPreviewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
        view.layer.insertSublayer(videoPreviewLayer, at: 0)
        return videoPreviewView
    }
    
    private func createStatsViews()
    {
        view.addSubview(statsView)

        // create stop button
        videoStopButton = createStopRecordingButton()
        
        // create a start recording button on top of the preview layer
        videoStartButton = createStartRecordingButton()
        videoStartButton.addTarget(self, action: #selector(VideoViewController.startVideoRecording), for: .touchUpInside)
        
        // add start button to the base view
        view.addSubview(videoStartButton)
        
        //add return button
        view.addSubview(returnButton)
        
        // create a timerDisplay
        videoTimerDisplay = createTimer()
        
        // start location service
        initializeLocationServices()
        
        startQueuedUpdates()
    }

    private func startTimer() -> Timer
    {
        return Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { Timer in
            self.videoTimerSeconds += 1
            if self.videoTimerSeconds == 60 {
                self.videoTimerMinutes += 1
                self.videoTimerSeconds = 0
            }
            var secondString = String(self.videoTimerSeconds)
            if self.videoTimerSeconds < 10 {
                secondString = "0" + secondString
            }
            var minuteString = String(self.videoTimerMinutes)
            if self.videoTimerMinutes < 10 {
                minuteString = "0" + minuteString
            }
            self.videoTimerDisplay.text = minuteString + ":" + secondString
        })
    }
    
    /**
     * Function to update main speed labels
     */
    private func updateSpeedLabels()
    {
        let speed = Int(round(self.currentSpeed))
        
        let hundredsDigit = speed / 100
        let tensDigit = speed % 100 / 10
        let onesDigit = speed % 10
        
        if hundredsDigit > self.lastHundredsDigit {
            //increasing for hundreds
            var diff = hundredsDigit - self.lastHundredsDigit
            var temp = self.lastHundredsDigit
            for _ in 0..<diff {
                self.hundredsDigitLabel.slideDown(self.speedDisplayRefreshInterval / Double(diff))
                temp += 1
                self.hundredsDigitLabel.text = String(temp)
            }
            
            //increasing for tens
            diff = abs(tensDigit - self.lastTensDigit)
            temp = self.lastTensDigit
            for _ in 0..<diff {
                temp -= 1
                if temp < 0 {
                    temp = 9
                }
                self.tensDigitLabel.slideDown(self.speedDisplayRefreshInterval / Double(diff))
                self.tensDigitLabel.text = String(temp)
            }
            
            //increasing for ones
            diff = abs(onesDigit - self.lastOnesDigit)
            temp = self.lastOnesDigit
            for _ in 0..<diff {
                temp += 1
                if temp >= 10 {
                    temp = 0
                }
                self.onesDigitLabel.slideDown(self.speedDisplayRefreshInterval / Double(diff))
                self.onesDigitLabel.text = String(temp)
            }
        }
        else if hundredsDigit < self.lastHundredsDigit {
            //decreasing for hundreds
            var diff = self.lastHundredsDigit - hundredsDigit
            var temp = self.lastHundredsDigit
            for _ in 0..<diff {
                self.hundredsDigitLabel.slideUp(self.speedDisplayRefreshInterval / Double(diff))
                temp -= 1
                self.hundredsDigitLabel.text = String(temp)
                
            }
            
            //decreasing for tens
            diff = abs(tensDigit - self.lastTensDigit)
            temp = self.lastTensDigit
            for _ in 0..<diff {
                temp -= 1
                if temp < 0 {
                    temp = 9
                }
                self.tensDigitLabel.slideUp(self.speedDisplayRefreshInterval / Double(diff))
                self.tensDigitLabel.text = String(temp)
            }
            
            //decreasing for ones
            diff = abs(onesDigit - self.lastOnesDigit)
            temp = self.lastOnesDigit
            for _ in 0..<diff {
                temp -= 1
                if temp < 0 {
                    temp = 9
                }
                self.onesDigitLabel.slideUp(self.speedDisplayRefreshInterval / Double(diff))
                self.onesDigitLabel.text = String(temp)
            }
            
        }
        else { //hundredsDigit the same, using tensDigit
            if self.lastTensDigit > tensDigit { //should show decreasing animation
                //decrease for tens
                var diff = abs(self.lastTensDigit - tensDigit)
                var temp = self.lastTensDigit
                for _ in 0..<diff {
                    temp -= 1
                    if temp < 0 {
                        temp = 9
                    }
                    self.tensDigitLabel.slideUp(self.speedDisplayRefreshInterval / Double(diff))
                    self.tensDigitLabel.text = String(temp)
                }
                
                //decrease for ones
                diff = abs(onesDigit - self.lastOnesDigit)
                temp = self.lastTensDigit
                for _ in 0..<diff {
                    temp -= 1
                    if temp < 0 {
                        temp = 9
                    }
                    self.onesDigitLabel.slideUp(self.speedDisplayRefreshInterval / Double(diff))
                    self.onesDigitLabel.text = String(temp)
                }
            }
            else if self.lastTensDigit < tensDigit { // should show increasing
                //increase for tens
                var diff = abs(tensDigit - self.lastTensDigit)
                var temp = self.lastTensDigit
                for _ in 0..<diff {
                    temp += 1
                    if temp >= 10 {
                        temp = 0
                    }
                    self.tensDigitLabel.slideDown(self.speedDisplayRefreshInterval / Double(diff))
                    self.tensDigitLabel.text = String(temp)
                }
                
                //increase for ones
                diff = abs(onesDigit - self.lastOnesDigit)
                temp = self.lastOnesDigit
                for _ in 0..<diff {
                    temp += 1
                    if temp >= 10 {
                        temp = 0
                    }
                    self.onesDigitLabel.slideDown(self.speedDisplayRefreshInterval / Double(diff))
                    self.onesDigitLabel.text = String(temp)
                }
            }
            else { //tens digit the same, compare ones digit
                if self.lastOnesDigit < onesDigit { //should show increasing
                    let diff = abs(onesDigit - self.lastOnesDigit)
                    var temp = self.lastOnesDigit
                    for _ in 0..<diff {
                        temp += 1
                        if temp >= 10 {
                            temp = 0
                        }
                        self.onesDigitLabel.slideDown(self.speedDisplayRefreshInterval / Double(diff))
                        self.onesDigitLabel.text = String(temp)
                    }
                }
                else if self.lastOnesDigit > onesDigit { //should show descreasing
                    let diff = abs(onesDigit - self.lastOnesDigit)
                    var temp = self.lastOnesDigit
                    for _ in 0..<diff {
                        temp -= 1
                        if temp < 0 {
                            temp = 9
                        }
                        self.onesDigitLabel.slideUp(self.speedDisplayRefreshInterval / Double(diff))
                        self.onesDigitLabel.text = String(temp)
                    }
                }
            }
        }
        
        self.lastHundredsDigit = hundredsDigit
        self.lastTensDigit = tensDigit
        self.lastOnesDigit = onesDigit
    }
    
    func startQueuedUpdates() {
        if cmManager.isDeviceMotionAvailable {
            cmManager.deviceMotionUpdateInterval = deviceMotionRefreshInterval
            cmManager.showsDeviceMovementDisplay = false
            
            cmManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue.main, withHandler: { (data, error) in
                // Make sure the data is valid before accessing it.
                if let validData = data {
                    // Get the attitude relative to the magnetic north reference frame.
                    let acceleration = validData.userAcceleration
                    
//                    print("User acceleration: \(acceleration)")
//                    print("Gravity: \(validData.gravity)")
                    
                    self.accelerationTimelines.append((Date(), -acceleration.z))
                    
                    //calculate instant delta speed for later usage
                    var deltaSpeed = -acceleration.z * self.deviceMotionRefreshInterval * 9.81 * 3.6
                    
                    //update throttle and brake indication according to deltaSpeed
//                    self.brakeAndThrottleUpdate(deltaSpeed)

                    if self.currentSpeed + deltaSpeed < 0 {
                        //important to adjust deltaSpeed for speed strip calculation
                        deltaSpeed = -self.currentSpeed
                    }
                    //update current speed
                    self.currentSpeed = self.currentSpeed + deltaSpeed
                    
                    self.gravityIndicationUpdate(gravityAcceleration: validData.userAcceleration)
                    
                    self.lastAcceleration = acceleration.z
                }
            })
        }
    }
    
    private func gravityIndicationUpdate(gravityAcceleration gravity: CMAcceleration)
    {
        //x, z
        UIView.animate(withDuration: deviceMotionRefreshInterval) {
//            print(gravity)

            let multiplyer = 50.0
            var yOffset = multiplyer * gravity.z
            if abs(yOffset) > self.gravityContainerHeight / 2 {
                yOffset = yOffset / abs(yOffset) * floor(self.gravityContainerHeight / 2 - 5)
            }
            
            var xOffset = multiplyer * gravity.y
            if abs(xOffset) > self.gravityContainerWidth / 2 {
                xOffset = xOffset / abs(xOffset) * floor(self.gravityContainerWidth / 2 - 5)
            }
            
//            print("xOffset \(gravity.y)")
//            print("yOffset \(gravity.z)")
//            print("x \(gravity.x)")
            
            if let yConstraint = self.gravityCrossHairYConstraint {
                yConstraint.isActive = false
            }
            UIView.animate(withDuration: self.deviceMotionRefreshInterval, animations: {
                self.gravityCrossHairYConstraint = self.gravityCrossHair.centerYAnchor.constraint(equalTo: self.gravityContainer.centerYAnchor, constant: CGFloat(yOffset))
                self.gravityCrossHairYConstraint!.isActive = true
            })
            
            if let xConstraint = self.gravityCrossHairXConstraint {
                xConstraint.isActive = false
            }
            
            UIView.animate(withDuration: self.deviceMotionRefreshInterval, animations: {
                self.gravityCrossHairXConstraint = self.gravityCrossHair.centerXAnchor.constraint(equalTo: self.gravityContainer.centerXAnchor, constant: CGFloat(xOffset))
                self.gravityCrossHairXConstraint!.isActive = true
            })
        }
    }
    
    private func brakeAndThrottleUpdate(_ deltaSpeed: Double)
    {
        if currentSpeed == 0 {
            self.brakeActive = true
            self.brakeAmber = false
            self.throttleActive = false
        }
        else if deltaSpeed >= -0.05 { // throttle is pressed
            self.throttleActive = true
            self.brakeActive = false
        }
        else if deltaSpeed < -0.20 { // decelerating
            self.brakeActive = true
            self.brakeAmber = false
            self.throttleActive = false
        }
        else if deltaSpeed < -0.15 {
            self.brakeActive = true
            self.brakeAmber = true
            self.throttleActive = false
        }
        else {
            self.brakeActive = false
            self.throttleActive = false
            self.brakeAmber = false
        }
    }
    
    // MARK: - Private functions to create buttons and labels
    // Helper function to create a video control button
    private func createControlButton(origin: CGPoint, size: CGSize,  backgroundImage resourceName: String) -> UIButton
    {
        let buttonFrame = CGRect(origin: origin, size: size)
        let button = UIButton(frame: buttonFrame)
        button.setBackgroundImage(UIImage(named: resourceName), for: .normal)
        return button
    }
    
    private func createStartRecordingButton() -> UIButton!
    {
        let screenBounds = UIScreen.main.bounds
        let screenHalfWidth = floor(screenBounds.width / 2.0)
        
        let width: CGFloat = 80.0
        let x: CGFloat = screenHalfWidth - width / 2.0
        let y: CGFloat = screenBounds.height * 0.8
        let origin = CGPoint(x: x, y: y)
        let size = CGSize(width: width, height: width)
        
        let button = createControlButton(origin: origin, size: size, backgroundImage: "record-outlined")
        return button
    }
    
    private func createStopRecordingButton() -> UIButton!
    {
        let screenBounds = UIScreen.main.bounds
        let screenHalfWidth = floor(screenBounds.width / 2.0)
        
        let width: CGFloat = 80.0
        let x: CGFloat = screenHalfWidth - width / 2.0
        let y: CGFloat = screenBounds.height * 0.8
        let origin = CGPoint(x: x, y: y)
        let size = CGSize(width: width, height: width)
        
        let button = createControlButton(origin: origin, size: size, backgroundImage: "record-stop")
        return button
    }
    
    private func createTimer() -> UILabel!
    {
        let timerHeight: CGFloat = 20.0
        let margin: CGFloat = 5.0
        let stopButtonFrame = videoStopButton.frame
        let origin = CGPoint(x: stopButtonFrame.origin.x + margin, y: stopButtonFrame.origin.y - timerHeight - margin)
        let size = CGSize(width: stopButtonFrame.width - margin * 2, height: 20)
        
        let frame = CGRect(origin: origin, size: size)
        let videoTimerDisplay = UILabel(frame: frame)
        videoTimerDisplay.text = "00:00"
        videoTimerDisplay.textAlignment = .center
        videoTimerDisplay.backgroundColor = labelColor
        
        return videoTimerDisplay
    }
    
    // MARK: - Location services
    private func initializeLocationServices()
    {
        print("Trying to initialize location services...")
        locationManager = CLLocationManager()
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            // Request when-in-use authorization initially
            locationManager.requestWhenInUseAuthorization()
            
        case .restricted, .denied:
            // Disable location features
            fatalError("User has denied location services.")
            
        case .authorizedWhenInUse:
            // Enable basic location features
            break
            
        case .authorizedAlways:
            // Enable any of your app's location features
            break
        }

        // Do not start services that aren't available.
        if !CLLocationManager.locationServicesEnabled() {
            // Location services is not available.
            print("Location service not available...")
            return
        }
        // Configure and start the service.
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
        print("location service started...")
    }
}

extension VideoViewController: CLLocationManagerDelegate
{
    func locationManager(_ manager: CLLocationManager,  didUpdateLocations locations: [CLLocation])
    {
        if let lastLocation = locations.last {
            lastSpeed = lastLocation.speed < 0 ? 0 : lastLocation.speed * 3.6
            
            var deltaSpeed = 0.0
            let accTimelinesCopy = accelerationTimelines
            accelerationTimelines = []
            for acData in accTimelinesCopy {
                if lastLocation.timestamp <= acData.date {
                    continue
                }
                else {
                    deltaSpeed += acData.acceleration * deviceMotionRefreshInterval * 9.81 * 3.6
                }
            }
            currentSpeed = lastSpeed + deltaSpeed
            if currentSpeed < 0 {
                currentSpeed = 0
            }
            
//            lastSpeed = currentSpeed
//
//            let speed = Double.random(in: 1...200)
//
//            currentSpeed = speed
            
            
            if deltaSpeed >= 0 {
                self.throttleActive = true
                self.brakeActive = false
            }
            
            else {
                self.throttleActive = false
                self.brakeActive = true
            }
            
            let coords = decimalCoords(toDMSFormat: lastLocation.coordinate)
            
            self.latitudeContainer.text = coords.latitude
            self.longitudeContainer.text = coords.longitude
        }
    }
    
    private func pinBackground(_ view: UIView, to stackView: UIStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stackView.insertSubview(view, at: 0)
        view.pin(to: stackView)
    }
    
    /*
    ** Function to convert CLLocationCoordinate2D object to DMS(Degree, Minute, Second) format
    */
    private func decimalCoords(toDMSFormat coords: CLLocationCoordinate2D) -> (latitude: String, longitude: String)
    {
        let latitude = coords.latitude
        let longitude = coords.longitude
        
        var degree = Int(latitude)
        var fraction = latitude.truncatingRemainder(dividingBy: 1.0)
        var value = fraction * 60
        var minutes = Int(value)
        fraction = value.truncatingRemainder(dividingBy: 1.0)
        var seconds = numberFormatter.string(from: NSNumber(value: fraction * 60)) ?? ""
        
        let latitudeString = String(format: "%d°%d'%@''%@", abs(degree), minutes, seconds, degree >= 0 ? "N" : "S")
        
        degree = Int(longitude)
        fraction = longitude.truncatingRemainder(dividingBy: 1.0)
        value = fraction * 60
        minutes = Int(value)
        fraction = value.truncatingRemainder(dividingBy: 1.0)
        seconds = numberFormatter.string(from: NSNumber(value: fraction * 60)) ?? ""
        
        let longitudeString = String(format: "%d°%d'%@''%@", abs(degree), minutes, seconds, degree >= 0 ? "E" : "W")
        return (latitude: latitudeString, longitude: longitudeString)
    }
}

extension VideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        if output == videoDataOutput {
            
            //Important: Correct your video orientation from your device orientation
            connection.videoOrientation = .landscapeLeft
            
            guard isRecordingStarted, canWrite() else { return }
            
            if sessionAtSourceTime == nil {
                sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                videoWriter.startSession(atSourceTime: sessionAtSourceTime!)
            }
            
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let context = CGContext.init(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!

    //        context.saveGState()
    //        context.translateBy(x: CGFloat(context.width), y: 0)
    //        context.translateBy(x: CGFloat(context.width), y: 0)
    //        speedString.draw(in: renderBounds, withAttributes: attrs)
    //        context?.clear(UIScreen.main.bounds)
    //        context?.draw(latitudeDisplay.asImage().cgImage!, in: renderBounds)
    //        context.scaleBy(x: 1.0, y: 1.0)
    //        context.rotate(by: CGFloat(Double.pi * 90 / 180))
    //        context.translateBy(x: 0, y: -CGFloat(context.width))

    //        UIImageWriteToSavedPhotosAlbum(outputImage, nil, nil, nil)
            context.draw(statsViewSnapshot.cgImage!, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
    //        context.restoreGState()
            
            if videoWriterInputPixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                videoWriterInputPixelBufferAdaptor.append(pixelBuffer, withPresentationTime: timestamp)
            }
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        else if output == audioDataOutput,
            audioWriterInput.isReadyForMoreMediaData {
                //Write audio buffer
                audioWriterInput.append(sampleBuffer)
        }
    }
    
    func canWrite() -> Bool {
        return isRecordingStarted
            && videoWriter != nil
            && videoWriter.status == .writing
    }
}

