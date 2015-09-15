//
//  TimeLapseBuilder.swift
//
//  Created by Adam Jensen on 5/10/15.
//  Copyright (c) 2015 Adam Jensen. All rights reserved.
//

import AVFoundation
import UIKit

let kErrorDomain = "TimeLapseBuilder"
let kFailedToStartAssetWriterError = 0
let kFailedToAppendPixelBufferError = 1

public class TimeLapseBuilder: NSObject {
  let photoURLs: [String]
  var videoWriter: AVAssetWriter?
  
  public init(photoURLs: [String]) {
    self.photoURLs = photoURLs
    
    super.init()
  }
  
  public func build(progress: (NSProgress -> Void), success: (NSURL -> Void), failure: (NSError -> Void)) {
    let inputSize = CGSize(width: 600, height: 600)
    let outputSize = CGSize(width: 600, height: 600)
    var error: NSError?
    
    let fileManager = NSFileManager.defaultManager()
    let urls = fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
    guard let documentDirectory: NSURL = urls.first else {
      fatalError("documentDir Error")
    }
    
    let videoOutputURL = documentDirectory.URLByAppendingPathComponent("AssembledVideo.mov")
    
    if NSFileManager.defaultManager().fileExistsAtPath(videoOutputURL.path!) {
      do {
        try NSFileManager.defaultManager().removeItemAtPath(videoOutputURL.path!)
      }catch{
        fatalError("Unable to delete file: \(error) : \(__FUNCTION__).")
      }
    }
    
    guard let videoWriter = try? AVAssetWriter(URL: videoOutputURL, fileType: AVFileTypeQuickTimeMovie) else{
      fatalError("AVAssetWriter error")
    }
    
    let outputSettings = [
      AVVideoCodecKey  : AVVideoCodecH264,
      AVVideoWidthKey  : NSNumber(float: Float(outputSize.width)),
      AVVideoHeightKey : NSNumber(float: Float(outputSize.height)),
    ]
    
    guard videoWriter.canApplyOutputSettings(outputSettings, forMediaType: AVMediaTypeVideo) else {
      fatalError("Negative : Can't apply the Output settings...")
    }
    
    let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)
    
    let sourcePixelBufferAttributesDictionary = [
      kCVPixelBufferPixelFormatTypeKey as String: NSNumber(unsignedInt: kCVPixelFormatType_32ARGB),
      kCVPixelBufferWidthKey as String: NSNumber(float: Float(inputSize.width)),
      kCVPixelBufferHeightKey as String: NSNumber(float: Float(inputSize.height)),
//      kCVPixelBufferCGImageCompatibilityKey as String: NSNumber(bool: true),
//      kCVPixelBufferCGBitmapContextCompatibilityKey as String: NSNumber(bool: true)
    ]
    
    let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoWriterInput,
      sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
    )
    
    assert(videoWriter.canAddInput(videoWriterInput))
    videoWriter.addInput(videoWriterInput)
    
    if videoWriter.startWriting() {
      videoWriter.startSessionAtSourceTime(kCMTimeZero)
      assert(pixelBufferAdaptor.pixelBufferPool != nil)
      
      let media_queue = dispatch_queue_create("mediaInputQueue", nil)
      
      videoWriterInput.requestMediaDataWhenReadyOnQueue(media_queue, usingBlock: { () -> Void in
        let fps: Int32 = 1
        let frameDuration = CMTimeMake(1, fps)
        let currentProgress = NSProgress(totalUnitCount: Int64(self.photoURLs.count))
        
        var frameCount: Int64 = 0
        var remainingPhotoURLs = [String](self.photoURLs)
        
        while (videoWriterInput.readyForMoreMediaData && !remainingPhotoURLs.isEmpty) {
          let nextPhotoURL = remainingPhotoURLs.removeAtIndex(0)
          let lastFrameTime = CMTimeMake(frameCount, fps)
          let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)
          
          
          if !self.appendPixelBufferForImageAtURL(nextPhotoURL, pixelBufferAdaptor: pixelBufferAdaptor, presentationTime: presentationTime) {
            error = NSError(domain: kErrorDomain, code: kFailedToAppendPixelBufferError,
              userInfo: [
                "description": "AVAssetWriterInputPixelBufferAdapter failed to append pixel buffer",
                "rawError": videoWriter.error ?? "(none)"
              ])
            
            break
          }
          
          frameCount++
          
          currentProgress.completedUnitCount = frameCount
          progress(currentProgress)
        }
        
        videoWriterInput.markAsFinished()
        videoWriter.finishWritingWithCompletionHandler { () -> Void in
          if error == nil {
            success(videoOutputURL)
          }
        }
      })
    } else {
      error = NSError(domain: kErrorDomain, code: kFailedToStartAssetWriterError,
        userInfo: ["description": "AVAssetWriter failed to start writing"]
      )
    }
    
    if let error = error {
      failure(error)
    }
  }
  
  public func appendPixelBufferForImageAtURL(urlString: String, pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> Bool {
    var appendSucceeded = true
    
    autoreleasepool {
      if let image = UIImage(contentsOfFile: urlString) {
        
          var pixelBuffer: CVPixelBuffer? = nil
          let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &pixelBuffer)
      
          if let pixelBuffer = pixelBuffer where status == 0 {
            let managedPixelBuffer = pixelBuffer
        
            fillPixelBufferFromImage(image.CGImage!, pixelBuffer: managedPixelBuffer)
            
            appendSucceeded = pixelBufferAdaptor.appendPixelBuffer(pixelBuffer, withPresentationTime: presentationTime)
            
          } else {
            NSLog("error: Failed to allocate pixel buffer from pool")
          }
       }
    }
    
    return appendSucceeded
  }
  

  func fillPixelBufferFromImage(image: CGImage, pixelBuffer: CVPixelBuffer){
    let frameSize = CGSizeMake(CGFloat(CGImageGetWidth(image)), CGFloat(CGImageGetHeight(image)))
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0)
    let data = CVPixelBufferGetBaseAddress(pixelBuffer)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGBitmapContextCreate(data, Int(frameSize.width), Int(frameSize.height), 8, CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace, CGImageAlphaInfo.PremultipliedFirst.rawValue)
    CGContextDrawImage(context, CGRectMake(0, 0, CGFloat(CGImageGetWidth(image)), CGFloat(CGImageGetHeight(image))), image)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
  }
}
