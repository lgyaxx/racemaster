//
//  IndexViewController.swift
//  RaceMaster
//
//  Created by 我的小么么 on 2018/8/26.
//  Copyright © 2018年 赛道控. All rights reserved.
//

import UIKit

class IndexViewController: UIViewController
{
    @IBAction func takeVideo(_ sender: UIBarButtonItem) {
        VideoHelper.startMediaBrowser(delegate: self, sourceType: .camera)
    }
    
}

extension IndexViewController: UINavigationControllerDelegate
{
    
}

extension IndexViewController: UIImagePickerControllerDelegate
{
    
}
