// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018 赛道控. All rights reserved.

import UIKit
import AVFoundation

class VideoViewController: UIViewController
{
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureMovieFileOutput!
    private var videoStartButton: UIButton!
    private var videoStopButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let videoHelper = VideoHelper()
        videoHelper.startVideoRecorder()
        
        captureSession = videoHelper.getCaptureSession()
        videoOutput = videoHelper.getVideoOutput()
        
        //create video preview layer so we can see real timing video frames
        let videoPreviewView = createPreview()

        // create a start recording button on top of the preview layer
        videoStartButton = createStartRecordingButton()
        videoStartButton.addTarget(self, action: #selector(VideoViewController.startVideoRecording), for: .touchUpInside)
        
        // add preview to base view
        view.addSubview(videoPreviewView)
        // add start button to the base view
        view.addSubview(videoStartButton)
        
        // start data flow to show preview
        self.captureSession.startRunning()
    }
    
    @objc public func startVideoRecording()
    {
        print("Recording started...")
        // remove start button
        videoStartButton.removeFromSuperview()
        videoStopButton = createStopRecordingButton()
        view.addSubview(videoStopButton)
        videoStopButton.addTarget(self, action: #selector(VideoViewController.stopVideoRecording), for: .touchUpInside)
        
        
        // add stop button
        
        let documentDirectories = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = documentDirectories.first!
        let videoPath = documentDirectory.appendingPathComponent("test.mp4")
        
        try? FileManager.default.removeItem(at: videoPath)
        self.videoOutput.startRecording(to: videoPath, recordingDelegate: self)
        
    }
    
    @objc public func stopVideoRecording()
    {
        print("Stopping recording...")
        videoOutput.stopRecording()
        videoStopButton.removeFromSuperview()
        view.addSubview(videoStartButton)
    }
    
    
    public func createPreview() -> VideoPreviewView
    {
        // create base frame to show video preview
        let videoFrame = UIScreen.main.bounds
        let videoPreviewView = VideoPreviewView(frame: videoFrame)
        videoPreviewView.backgroundColor = UIColor.blue
        videoPreviewView.videoPreviewLayer.session = self.captureSession
        //        videoPreviewView.videoPreviewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
        return videoPreviewView
    }
    
    // Helper function to create a video control button
    private func createControlButton(origin: CGPoint, size: CGSize,  backgroundImage resourceName: String) -> UIButton
    {
        let buttonFrame = CGRect(origin: origin, size: size)
        let button = UIButton(frame: buttonFrame)
        button.setBackgroundImage(UIImage(named: resourceName), for: .normal)
        return button
    }
    
    private func createStartRecordingButton() -> UIButton
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
    
    private func createStopRecordingButton() -> UIButton
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
    
}

extension VideoViewController: AVCaptureFileOutputRecordingDelegate
{
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("FINISHED \(String(describing: error))")
        // save video to camera roll
        if error == nil {
            UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        }
    }
}
