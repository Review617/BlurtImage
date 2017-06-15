//
//  ViewController.m
//  图片模糊及毛玻璃效果
//
//  Created by TangYuan on 2017/6/15.
//  Copyright © 2017年 TangYuan. All rights reserved.
//

#import "ViewController.h"
#import <Accelerate/Accelerate.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imgView;
@property (nonatomic, strong) UIImage *textImage;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.textImage = [UIImage imageNamed:@"huihui.jpeg"];
}


// CoreImage 渲染比较慢，会造成卡机
- (IBAction)coreImage:(id)sender {
    
    CIContext *context = [CIContext contextWithOptions:nil];
    CIImage *inoutImage = [CIImage imageWithCGImage:_textImage.CGImage];
    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [filter setValue:inoutImage forKey:kCIInputImageKey];
    [filter setValue:@(3) forKey:@"inputRadius"]; // 模糊程度 0-10
    CIImage *outImage = [filter valueForKey:kCIOutputImageKey];
    CGImageRef ref = [context createCGImage:outImage fromRect:[outImage extent]];
    UIImage *blurImage = [UIImage imageWithCGImage:ref];

    // 非OC对象创建后要手动释放内存
    CGImageRelease(ref);
    
    _imgView.image = blurImage;
}

// vImage vImage属于Accelerate.Framework，需要导入 Accelerate下的 Accelerate头文件
- (IBAction)vImage:(id)sender {

    _imgView.image = nil;
    
    UIImage *maskImage = nil;
    CGFloat saturationDeltaFactor = 1.5; // 可修改调试
    CGFloat blurRadius = 2; // 可修改调试 数字越大越模糊
    
    CGRect imageRect = { CGPointZero, _textImage.size };
    UIImage *effectImage = _textImage;
    
    BOOL hasBlur = blurRadius > __FLT_EPSILON__;
    BOOL hasSaturationChange = fabs(saturationDeltaFactor - 1.) > __FLT_EPSILON__;
    if (hasBlur || hasSaturationChange) {
        UIGraphicsBeginImageContextWithOptions(_textImage.size, NO, [[UIScreen mainScreen] scale]);
        CGContextRef effectInContext = UIGraphicsGetCurrentContext();
        CGContextScaleCTM(effectInContext, 1.0, -1.0);
        CGContextTranslateCTM(effectInContext, 0, -_textImage.size.height);
        CGContextDrawImage(effectInContext, imageRect, _textImage.CGImage);
        
        vImage_Buffer effectInBuffer;
        effectInBuffer.data     = CGBitmapContextGetData(effectInContext);
        effectInBuffer.width    = CGBitmapContextGetWidth(effectInContext);
        effectInBuffer.height   = CGBitmapContextGetHeight(effectInContext);
        effectInBuffer.rowBytes = CGBitmapContextGetBytesPerRow(effectInContext);
        
        UIGraphicsBeginImageContextWithOptions(_textImage.size, NO, [[UIScreen mainScreen] scale]);
        CGContextRef effectOutContext = UIGraphicsGetCurrentContext();
        vImage_Buffer effectOutBuffer;
        effectOutBuffer.data     = CGBitmapContextGetData(effectOutContext);
        effectOutBuffer.width    = CGBitmapContextGetWidth(effectOutContext);
        effectOutBuffer.height   = CGBitmapContextGetHeight(effectOutContext);
        effectOutBuffer.rowBytes = CGBitmapContextGetBytesPerRow(effectOutContext);
        
        if (hasBlur) {

            CGFloat inputRadius = blurRadius * [[UIScreen mainScreen] scale];
            int radius = floor(inputRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
            if (radius % 2 != 1) {
                radius += 1;
            }
            vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
            vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
            vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
        }
        BOOL effectImageBuffersAreSwapped = NO;
        if (hasSaturationChange) {
            CGFloat s = saturationDeltaFactor;
            CGFloat floatingPointSaturationMatrix[] = {
                0.0722 + 0.9278 * s,  0.0722 - 0.0722 * s,  0.0722 - 0.0722 * s,  0,
                0.7152 - 0.7152 * s,  0.7152 + 0.2848 * s,  0.7152 - 0.7152 * s,  0,
                0.2126 - 0.2126 * s,  0.2126 - 0.2126 * s,  0.2126 + 0.7873 * s,  0,
                0,                    0,                    0,  1,
            };
            const int32_t divisor = 256;
            NSUInteger matrixSize = sizeof(floatingPointSaturationMatrix)/sizeof(floatingPointSaturationMatrix[0]);
            int16_t saturationMatrix[matrixSize];
            for (NSUInteger i = 0; i < matrixSize; ++i) {
                saturationMatrix[i] = (int16_t)roundf(floatingPointSaturationMatrix[i] * divisor);
            }
            if (hasBlur) {
                vImageMatrixMultiply_ARGB8888(&effectOutBuffer, &effectInBuffer, saturationMatrix, divisor, NULL, NULL, kvImageNoFlags);
                effectImageBuffersAreSwapped = YES;
            }
            else {
                vImageMatrixMultiply_ARGB8888(&effectInBuffer, &effectOutBuffer, saturationMatrix, divisor, NULL, NULL, kvImageNoFlags);
            }
        }
        if (!effectImageBuffersAreSwapped)
            effectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        if (effectImageBuffersAreSwapped)
            effectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    // Set up output context.
    UIGraphicsBeginImageContextWithOptions(_textImage.size, NO, [[UIScreen mainScreen] scale]);
    CGContextRef outputContext = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(outputContext, 1.0, -1.0);
    CGContextTranslateCTM(outputContext, 0, -_textImage.size.height);
    
    // Draw base image.
    CGContextDrawImage(outputContext, imageRect, _textImage.CGImage);
    
    /*
    // Draw effect image. 遮罩图
    if (hasBlur) {
        CGContextSaveGState(outputContext);
        if (maskImage) {
            CGContextClipToMask(outputContext, imageRect, maskImage.CGImage);
        }
        CGContextDrawImage(outputContext, imageRect, effectImage.CGImage);
        CGContextRestoreGState(outputContext);
    }
    
    // Add in color tint. 上色
    if (tintColor) {
        CGContextSaveGState(outputContext);
        CGContextSetFillColorWithColor(outputContext, tintColor.CGColor);
        CGContextFillRect(outputContext, imageRect);
        CGContextRestoreGState(outputContext);
    }
    */
    
    
    // Draw effect image.
    if (hasBlur) {
        CGContextSaveGState(outputContext);
        if (maskImage) {
            CGContextClipToMask(outputContext, imageRect, maskImage.CGImage);
        }
        CGContextDrawImage(outputContext, imageRect, effectImage.CGImage);
        CGContextRestoreGState(outputContext);
    }

    // Output image is ready.
    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    _imgView.image = outputImage;
}

// GPUImage
- (IBAction)GPUImage:(id)sender {
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"请前往github" message:@"https://github.com/524429264/iOS-UIImageBoxBlur" preferredStyle:(UIAlertControllerStyleAlert)];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:(UIAlertActionStyleCancel) handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    
    NSLog(@"https://github.com/524429264/iOS-UIImageBoxBlur");
}


// 毛玻璃
- (IBAction)BlurEffect:(id)sender {
    
    _imgView.image = _textImage;
    
    
    /*
     UIBlurEffectStyleExtraLight,
     UIBlurEffectStyleLight,
     UIBlurEffectStyleDark
     */
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:effect];
//    [effectView setAlpha:0.8];
    effectView.frame = CGRectMake(0, 0, _imgView.frame.size.width, _imgView.frame.size.height);
    [_imgView addSubview:effectView];
}

@end
