// Author: Eagle Luo
// Created: 2018/9/24
// Copyright © 2018 赛道控. All rights reserved.

import UIKit

class Circle: UIView
{
    override func layoutSubviews() {
        layer.cornerRadius = bounds.size.width / 2;
    }
}
