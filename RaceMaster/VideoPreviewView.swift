//
//  PreviewView.swift
//  RaceMaster
//
// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018


import UIKit
import AVFoundation

class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    /// Convenience wrapper to get layer as its statically known type.
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
