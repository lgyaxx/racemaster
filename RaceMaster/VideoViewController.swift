// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018 赛道控. All rights reserved.

import UIKit
import AVFoundation
import CoreLocation
import Foundation
import CoreMotion


extension UIView {
    func slideUp(_ duration:CFTimeInterval) {
        let animation:CATransition = CATransition()
        animation.timingFunction = CAMediaTimingFunction(name:
            CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType.push
        animation.subtype = CATransitionSubtype.fromTop
        animation.duration = duration
        layer.add(animation, forKey: CATransitionType.push.rawValue)
    }
    
    func slideDown(_ duration:CFTimeInterval) {
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
}

extension UIView {
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            self.layer.render(in: rendererContext.cgContext)
        }
    }
}

class VideoViewController: UIViewController
{
    // MARK: - Variables
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
    
    private let labelColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.5)
    
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
    private var latitudeDisplay: UILabel!
    private var longitudeDisplay: UILabel!
    private var latitudeDisplayRect: CGRect!
    
    private lazy var speedDisplayBackground: UIView = {
        let view = UIView()
        view.backgroundColor = labelColor
        view.layer.cornerRadius = 5.0
        return view
    }()
    private var speedLabelSize: CGSize!
    private var speedLabelRect: CGRect!
    @IBOutlet var rawSpeed: UILabel!
    @IBOutlet var speedDisplay: UIStackView!
    @IBOutlet var speedReading: UILabel!
    private lazy var cmManager = CMMotionManager()
    private var currentSpeed: Double = 0
    private var lastSpeed: Double = 0
    private var lastTimestamp: Date = Date()
    private var lastAcceleration: Double = 0.0
    private var speedLock = false
    
    private weak var timer: Timer!
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        return formatter
    } ()
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
    
        captureSession.sessionPreset = .medium
        
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
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
            self.setupCaptureSession()
            return
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCaptureSession()
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
            
            let videoWidth = self.view.bounds.width + 1
            let videoHeight = ceil(videoWidth * 9.0 / 16.0)
            //Add video input 16:9
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2300000,
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
        super.viewDidLoad()
        
        testAuthorizedToUseCamera()
        
        
        // force landscape before setting up video preview
        let orientation = UIInterfaceOrientation.landscapeLeft.rawValue
        UIDevice.current.setValue(orientation, forKey: "orientation")
        
        //create video preview layer so we can see real timing video frames
        videoPreviewView = createPreview()
        videoPreviewLayer = videoPreviewView.videoPreviewLayer
        videoFrameRect = videoPreviewLayer.bounds

        pinBackground(speedDisplayBackground, to: speedDisplay)
        createStatsViews()
        
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true, block: { Timer in
            self.speedReading.text = String(ceil(self.currentSpeed))
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
            
            speedLabelRect = speedDisplayBackground.bounds
            latitudeDisplayRect = latitudeDisplay.bounds
            videoWriter = writer
            
            let recordingClock = self.captureSession.masterClock!
            videoWriter.startWriting()
            videoWriter.startSession(atSourceTime: CMClockGetTime(recordingClock))
            print("Start recording...")
            isRecordingStarted = true
        }
    }
    
    @objc public func stopVideoRecording()
    {
        print("Stopping recording...")
        timer.invalidate()
        //TODO: stop recording
        
        videoStopButton.removeFromSuperview()
        videoTimerDisplay.removeFromSuperview()
        view.addSubview(videoStartButton)
        
        if let writer = videoWriter {
            writer.finishWriting {
                print("Recording finished")
                UISaveVideoAtPathToSavedPhotosAlbum(writer.outputURL.path, nil, nil, nil)
            }
            self.isRecordingStarted = false
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
        // add location data
        latitudeDisplay = createLatitudeDisplay()
        longitudeDisplay = createLongitudeDisplay()
        speedDisplay = createSpeedDisplay()
        
        statsView.addSubview(latitudeDisplay)
        statsView.addSubview(longitudeDisplay)
        view.addSubview(statsView)

        // create stop button
        videoStopButton = createStopRecordingButton()
        
        // create a start recording button on top of the preview layer
        videoStartButton = createStartRecordingButton()
        videoStartButton.addTarget(self, action: #selector(VideoViewController.startVideoRecording), for: .touchUpInside)
        
        // add start button to the base view
        view.addSubview(videoStartButton)
        
        //
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
    
    func startQueuedUpdates() {
        if cmManager.isDeviceMotionAvailable {
            cmManager.deviceMotionUpdateInterval = 1 / 30
            cmManager.showsDeviceMovementDisplay = false
            
            cmManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
                // Make sure the data is valid before accessing it.
//                if let validData = data {
//                    // Get the attitude relative to the magnetic north reference frame.
////                    let gravity = validData.gravity
//                    let acceleration = validData.userAcceleration
//
////                    print("Gravity: \(gravity)")
////                    print("Acceleration: \(acceleration)")
////                    print("Heading \(validData.heading)")
//
//                    let deltaSpeed = -(acceleration.z + self.lastAcceleration) / 2 * (1/30) * 3.6
//                    var tmpSpeed = self.lastSpeed + deltaSpeed
//                    if tmpSpeed < 0 {
//                        tmpSpeed = 0
//                    }
//
//
//                    self.currentSpeed = tmpSpeed
////                    print("CurrentSpeed: \(self.currentSpeed)")
//
//                    self.lastAcceleration = acceleration.z
//                }
//            })
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
    
    private func createLatitudeDisplay() -> UILabel
    {
        let screenBounds = UIScreen.main.bounds
        
        let frame = CGRect(origin: CGPoint(x: screenBounds.width * 0.8, y: screenBounds.height * 0.8), size: CGSize(width: 300, height: 20))
        
        let latitudeDisplay = UILabel(frame: frame)
        latitudeDisplay.text = ""
        latitudeDisplay.backgroundColor = labelColor
        
        return latitudeDisplay
    }
    
    private func createLongitudeDisplay() -> UILabel
    {
        let height: CGFloat = 20
        let offset: CGFloat = 5
        let latitudeFrame = latitudeDisplay.frame
        let origin = CGPoint(x: latitudeFrame.origin.x, y: latitudeFrame.origin.y + height + offset)
        let frame = CGRect(origin: origin, size: CGSize(width: 300, height: height))
        
        let longitudeDisplay = UILabel(frame: frame)
        longitudeDisplay.text = ""
        longitudeDisplay.backgroundColor = labelColor
        
        return longitudeDisplay
    }
    
    private func createSpeedDisplay() -> UIStackView
    {
        let screenBounds = UIScreen.main.bounds
        
        let frame = CGRect(origin: CGPoint(x: screenBounds.width * 0.8, y: screenBounds.height * 0.7), size: CGSize(width: 150, height: 20))
        
        let speedDisplay = UIStackView(frame: frame)
        speedDisplay.backgroundColor = labelColor
        
        return speedDisplay
    }
}

extension VideoViewController: AVCaptureFileOutputRecordingDelegate
{
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        if let e = error  {
            print("\(e)")
            return
        }
        
//        //create AVAsset for testing
//        let video = AVAsset(url: outputFileURL)
//        print("Duration of captured video in second(s): \(video.duration.seconds)")
//
//        let videoTracks = video.tracks(withMediaType: .video)
//        let videoTrack = videoTracks[0]
//        let videoDuration = video.duration
//        let videoTimeRange = CMTimeRange(start: CMTime.zero, duration: videoDuration)
//
//        var error: NSError?
//        let composition = AVMutableComposition()
//        do {
//            try composition.insertTimeRange(videoTrack.timeRange, of: video, at: videoTrack.timeRange.start)
//        } catch let outError: NSError {
//            print("Error calling insertTimeRange: \(outError)")
//        }
//
//        let formatsKey = "availableMetadataFormats"
//        video.loadValuesAsynchronously(forKeys: [formatsKey]) {
//            var error: NSError? = nil
//            let status = video.statusOfValue(forKey: formatsKey, error: &error)
//            if status == .loaded {
//                for format in video.availableMetadataFormats {
//                    let metadata = video.metadata(forFormat: format)
//                    print("\(metadata)")
//                }
//            }
//        }
        
        
        // save video to camera roll
        if error == nil {
            print("Output file path is: " + outputFileURL.path)
            UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        }
    }
}

extension VideoViewController: CLLocationManagerDelegate
{
    func locationManager(_ manager: CLLocationManager,  didUpdateLocations locations: [CLLocation])
    {
        if let lastLocation = locations.last {
            lastSpeed = lastLocation.speed < 0 ? 0 : lastLocation.speed * 3.6
            
            if let motion = cmManager.deviceMotion {
                let difference = Calendar.current.dateComponents([.nanosecond, .second], from: lastTimestamp, to: lastLocation.timestamp)
                lastTimestamp = lastLocation.timestamp
                
                let acceleration = motion.userAcceleration.z
                let deltaSpeed = -(acceleration + lastAcceleration) / 2 * Double(difference.second!) * 3.6
                print("delta spd: \(deltaSpeed)")
                var tmpSpeed = self.lastSpeed + deltaSpeed
                if tmpSpeed < 0 {
                    tmpSpeed = 0
                }
                currentSpeed = tmpSpeed
                lastAcceleration = acceleration
            }
            rawSpeed.backgroundColor = labelColor
            rawSpeed.text = "GPS Raw: " + String(lastSpeed) + "km/h"
            
            
            
            
            let coords = decimalCoords(toDMSFormat: lastLocation.coordinate)
            
            self.latitudeDisplay.text = coords.latitude
            self.longitudeDisplay.text = coords.longitude
            

    //            speed = Int.random(in: 1...30)
            

    //            currentSpeed = speed
    //
    //            if lastSpeed != currentSpeed {

    //
    //                print("time interval: \(interval)")
    //                interval = interval / 2000000000.0 / Double(abs(currentSpeed - lastSpeed))
    //                updateSpeedReading(interval: interval)
    //            }
            
        }
    }
    
    private func speedChangeFunc(_ changeFrom: Int, _ changeTo: Int) -> Int
    {
        if changeTo > changeFrom {
        return changeFrom + 1
        }
        return changeFrom - 1
    }
    
    private func pinBackground(_ view: UIView, to stackView: UIStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stackView.insertSubview(view, at: 0)
        view.pin(to: stackView)
    }
//
//    private func updateSpeedReading(interval: Double)
//    {
//        let changeFrom = lastSpeed
//        let changeTo = currentSpeed
//
//        let nextUpdate: [String: Any] = ["changeTo": speedChangeFunc(changeFrom, changeTo), "until": changeTo, "interval": interval]
//        Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(updateSpeed), userInfo: nextUpdate, repeats: false)
//    }
//
//    @objc private func updateSpeed(_ timer: Timer)
//    {
//        var nextUpdate = timer.userInfo as! [String: Any]
//        if let until = nextUpdate["until"] as? Int, let changeTo = nextUpdate["changeTo"] as? Int, self.currentSpeed == until, let interval = nextUpdate["interval"] as? Double { // new speed update hasn't occured, continue updating
//            speedReading.text = String(changeTo)
//            lastSpeed = changeTo
//            if changeTo != until {
//                nextUpdate["changeTo"] = speedChangeFunc(changeTo, until)
//                Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(updateSpeed), userInfo: nextUpdate, repeats: false)
//            }
//        }
//    }
    
    // digits will be of format [1: 0, 2: 1, 3:5, ...]
    private func getDigits(_ speed: Int) -> [Int: Int]
    {
        var digits = [Int: Int]()
        var speed = speed
        var index = 1
        repeat {
            digits[index] = speed % 10
            speed /= 10
            index += 1
        } while (speed != 0)
        print(digits)
        return digits
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
        
        //Important: Correct your video orientation from your device orientation
        connection.videoOrientation = .landscapeLeft
        
        guard isRecordingStarted, canWrite() else { return }
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
//        let attachments = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault, target: pixelBuffer, attachmentMode: CMAttachmentMode(kCMAttachmentMode_ShouldPropagate)) as? [CIImageOption: Any]
        
//        let ciImage = CIImage(cvImageBuffer: pixelBuffer, options: attachments)
//
//        let speedString = NSString.init(string: String(Int.random(in: 20...100)))
//        let attrs = [NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 16)!, NSAttributedString.Key.backgroundColor: labelColor, NSAttributedString.Key.foregroundColor: UIColor.black]
//        let stringSize = speedString.size(withAttributes: attrs)
        
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

        let outputImage = self.statsView.asImage().cgImage!
//        UIImageWriteToSavedPhotosAlbum(outputImage, nil, nil, nil)
//        context.draw(outputImage, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.draw(outputImage, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
//        context.restoreGState()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        if output == videoDataOutput {
            if isRecordingStarted, videoWriterInput.isReadyForMoreMediaData {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                //Write video buffer
//                videoWriterInput.append(sampleBuffer)
                videoWriterInputPixelBufferAdaptor.append(pixelBuffer, withPresentationTime: timestamp)
            }
        }
    }
    
    func canWrite() -> Bool {
        return isRecordingStarted
            && videoWriter != nil
            && videoWriter.status == .writing
    }
}

