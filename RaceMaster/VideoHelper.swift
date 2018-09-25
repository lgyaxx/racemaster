//
//  VideoHelper.swift
//  RaceMaster
//
// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018


import UIKit
import AVFoundation
import MobileCoreServices

class VideoHelper: NSObject
{
    private var captureSession: AVCaptureSession!
    private lazy var videoDataOutput = AVCaptureVideoDataOutput()
    private lazy var audioDataOutput = AVCaptureAudioDataOutput()
    
    // MARK: - Private Functions
    
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

    // MARK: - Public functions
    
    public func getCaptureSession() -> AVCaptureSession!
    {
        return self.captureSession
    }
    
    static func startMediaBrowser(delegate: UIViewController & UINavigationControllerDelegate & UIImagePickerControllerDelegate, sourceType: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else { return }
        
        let mediaUI = UIImagePickerController()
        mediaUI.sourceType = sourceType
        mediaUI.mediaTypes = [kUTTypeMovie as String]
        mediaUI.allowsEditing = true
        mediaUI.delegate = delegate
        delegate.present(mediaUI, animated: true, completion: nil)
    }
    
    public func startVideoRecorder()
    {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            self.setupCaptureSession()
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCaptureSession()
                }
            }
        case .denied: // The user has previously denied access.
            return
        case .restricted: // The user can't grant access due to restrictions.
            return
        }
        
    }

}

