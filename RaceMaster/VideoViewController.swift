// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018 赛道控. All rights reserved.

import UIKit
import AVFoundation
import CoreLocation
import Foundation

class VideoViewController: UIViewController
{
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureMovieFileOutput!
    private var videoStartButton: UIButton!
    private var videoStopButton: UIButton!
    private var videoTimerMinutes: Int = 0
    private var videoTimerSeconds: Int = 0
    private var videoTimerDisplay: UILabel!
    private var videoPreviewView: VideoPreviewView!
    private var locationManager: CLLocationManager!
    private var latitudeDisplay: UILabel!
    private var longitudeDisplay: UILabel!
    private var speedDisplay: UILabel!
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
    // MARK: - Device Orientation
    override var shouldAutorotate: Bool
    {
        return false
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask
    {
        return .landscapeLeft
    }
    // MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let videoHelper = VideoHelper()
        videoHelper.startVideoRecorder()
        
        captureSession = videoHelper.getCaptureSession()
        guard captureSession != nil else {
            print("Nil captureSession...exiting")
            return
        }
        videoOutput = videoHelper.getVideoOutput()
        
        // force landscape before setting up video preview
        let orientation = UIInterfaceOrientation.landscapeLeft.rawValue
        UIDevice.current.setValue(orientation, forKey: "orientation")
        
        //create video preview layer so we can see real timing video frames
        videoPreviewView = createPreview()
        
        createStatsViews()

        // start data flow to show preview
        self.captureSession.startRunning()
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
        self.videoOutput.startRecording(to: videoPath, recordingDelegate: self)
    }
    
    @objc public func stopVideoRecording()
    {
        print("Stopping recording...")
        timer.invalidate()
        videoOutput.stopRecording()
        videoStopButton.removeFromSuperview()
        videoTimerDisplay.removeFromSuperview()
        view.addSubview(videoStartButton)
    }
    
    
    public func createPreview() -> VideoPreviewView!
    {
        // create base frame to show video preview
        let videoFrame = UIScreen.main.bounds
        let videoPreviewView = VideoPreviewView(frame: videoFrame)
        videoPreviewView.backgroundColor = UIColor.blue
        videoPreviewView.videoPreviewLayer.session = self.captureSession
        videoPreviewView.videoPreviewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
        return videoPreviewView
    }
    
    private func createStatsViews()
    {
        // create stop button
        videoStopButton = createStopRecordingButton()
        
        // create a start recording button on top of the preview layer
        videoStartButton = createStartRecordingButton()
        videoStartButton.addTarget(self, action: #selector(VideoViewController.startVideoRecording), for: .touchUpInside)
        
        // add preview to base view
        view.addSubview(videoPreviewView)
        // add start button to the base view
        view.addSubview(videoStartButton)
        
        // create a timerDisplay
        videoTimerDisplay = createTimer()
        
        // add location data
        latitudeDisplay = createLatitudeDisplay()
        longitudeDisplay = createLongitudeDisplay()
        speedDisplay = createSpeedDisplay()
        view.addSubview(latitudeDisplay)
        view.addSubview(longitudeDisplay)
        view.addSubview(speedDisplay)
        // start location service
        initializeLocationServices()
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
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//                self.startTimer()
//            }
//        }
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
        videoTimerDisplay.backgroundColor = UIColor(red: 255, green: 255, blue: 255, alpha: 0.5)
        
        return videoTimerDisplay
    }
    
    // Mark: - Location services
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
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0  // In meters.
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
        print("location service started...")
    }
    
    private func createLatitudeDisplay() -> UILabel
    {
        let screenBounds = UIScreen.main.bounds
        
        let frame = CGRect(origin: CGPoint(x: screenBounds.width * 0.8, y: screenBounds.height * 0.8), size: CGSize(width: 300, height: 20))
        
        let latitudeDisplay = UILabel(frame: frame)
        latitudeDisplay.text = "纬度: "
        latitudeDisplay.backgroundColor = UIColor(red: 255, green: 255, blue: 255, alpha: 0.5)
        
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
        longitudeDisplay.text = "经度: "
        longitudeDisplay.backgroundColor = UIColor(red: 255, green: 255, blue: 255, alpha: 0.5)
        
        return longitudeDisplay
    }
    
    private func createSpeedDisplay() -> UILabel
    {
        let screenBounds = UIScreen.main.bounds
        
        let frame = CGRect(origin: CGPoint(x: screenBounds.width * 0.8, y: screenBounds.height * 0.7), size: CGSize(width: 120, height: 20))
        
        let speedDisplay = UILabel(frame: frame)
        speedDisplay.text = "速度: "
        speedDisplay.backgroundColor = UIColor(red: 255, green: 255, blue: 255, alpha: 0.5)
        
        return speedDisplay
    }
    
}

extension VideoViewController: AVCaptureFileOutputRecordingDelegate
{
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("FINISHED \(String(describing: error))")
        // save video to camera roll
        if error == nil {
            print("Output file path is: " + outputFileURL.path)
            UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        }
    }
}

extension VideoViewController: CLLocationManagerDelegate
{
    func locationManager(_ manager: CLLocationManager,  didUpdateLocations locations: [CLLocation]) {
        if let lastLocation = locations.last, latitudeDisplay != nil, longitudeDisplay != nil, speedDisplay != nil {
            print(lastLocation)
            let coords = decimalCoords(toDMSFormat: lastLocation.coordinate)
            
            self.latitudeDisplay.text = "纬度: " + coords.latitude
            self.longitudeDisplay.text = "经度: " + coords.longitude
            self.speedDisplay.text = "实时速度: " + String(lastLocation.speed)
        }
        else {
            print("Invalid location data.")
        }
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
        
        print("Latitude string: \(latitudeString)")
        
        degree = Int(longitude)
        fraction = longitude.truncatingRemainder(dividingBy: 1.0)
        value = fraction * 60
        minutes = Int(value)
        fraction = value.truncatingRemainder(dividingBy: 1.0)
        seconds = numberFormatter.string(from: NSNumber(value: fraction * 60)) ?? ""
        
        let longitudeString = String(format: "%d°%d'%@''%@", abs(degree), minutes, seconds, degree >= 0 ? "E" : "W")
        print("Longitude string: \(longitudeString)")
        return (latitude: latitudeString, longitude: longitudeString)
    }
}
