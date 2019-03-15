//
//  UIColor+Extension.m
//  NEStompDemo
//
//  Created by JimmyOu on 2018/7/30.
//  Copyright © 2018年 JimmyOu. All rights reserved.
//

#import "UIColor+Extension.h"

@implementation UIColor (Extension)
+ (UIColor *)randomColor {
    return [UIColor colorWithRed:(CGFloat)random() / (CGFloat)RAND_MAX
                           green:(CGFloat)random() / (CGFloat)RAND_MAX
                            blue:(CGFloat)random() / (CGFloat)RAND_MAX
                           alpha:1.0f];
}
@end
