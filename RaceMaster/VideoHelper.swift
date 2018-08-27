//
//  VideoHelper.swift
//  RaceMaster
//
//  Created by 我的小么么 on 2018/8/26.
//  Copyright © 2018年 赛道控. All rights reserved.
//

import UIKit
//import AVFoundation
import MobileCoreServices

class VideoHelper
{
    static func startMediaBrowser(delegate: UIViewController & UINavigationControllerDelegate & UIImagePickerControllerDelegate, sourceType: UIImagePickerControllerSourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else { return }
        
        let mediaUI = UIImagePickerController()
        mediaUI.sourceType = sourceType
        mediaUI.mediaTypes = [kUTTypeMovie as String]
        mediaUI.allowsEditing = true
        mediaUI.delegate = delegate
        delegate.present(mediaUI, animated: true, completion: nil)
    }
}
