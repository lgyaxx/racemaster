// Author: Eagle Luo
// Created: 2018/8/27
// Copyright © 2018 赛道控. All rights reserved.

import UIKit

class VideoViewController: UIViewController
{
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let videoHelper = VideoHelper()
        videoHelper.startVideoRecorder()
        
        guard let videoCaptureSession = videoHelper.getCaptureSession() else {
            return
        }
        
        
        let videoFrame = UIScreen.main.bounds
        let videoPreviewView = VideoPreviewView(frame: videoFrame)
        videoPreviewView.backgroundColor = UIColor.blue
        videoPreviewView.videoPreviewLayer.session = videoCaptureSession
        
        view.addSubview(videoPreviewView)
        
        let eagleFrameWidth: CGFloat = 100.0
        let screenBounds = UIScreen.main.bounds
        let eagleFrame = CGRect(origin: CGPoint(x: screenBounds.width / 2 - eagleFrameWidth / 2, y: screenBounds.height - eagleFrameWidth * 2), size: CGSize(width: eagleFrameWidth, height: eagleFrameWidth))
        let eagleView = UILabel(frame: eagleFrame)
        eagleView.backgroundColor = UIColor.blue
        eagleView.textColor = UIColor.white
        eagleView.text = "Eagle Genius"
        
        view.addSubview(eagleView)
        
        
        videoCaptureSession.startRunning()
    }
}
