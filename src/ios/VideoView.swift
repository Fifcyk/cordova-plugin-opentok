//
//  VideoViewController.swift
//  roller
//
//  Created by Devin Andrews on 12/16/14.
//
//

import Foundation
import UIKit
import AVFoundation

public @objc(Video) class VideoView : NSObject {
    
    var captureSession = AVCaptureSession()
    var previewLayer : AVCaptureVideoPreviewLayer?
    var captureDevice : AVCaptureDevice?
    var previousInput : AVCaptureDeviceInput?
    
    public func getVideo(view: UIView) {
        let devices = AVCaptureDevice.devices()
        
        for device in devices {
            if(device.hasMediaType(AVMediaTypeVideo)) {
                if(device.position == AVCaptureDevicePosition.Back) {
                    captureDevice = device as? AVCaptureDevice
                }
            }
        }
        
        if captureDevice != nil {
            var err : NSError? = nil
            
            previousInput = AVCaptureDeviceInput(device: captureDevice, error: &err)
            captureSession.addInput(previousInput)
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.name = "VideoView"
            view.layer.insertSublayer(previewLayer, atIndex: 0)
            
            previewLayer?.frame = view.layer.frame
            
            var bounds:CGRect = view.layer.bounds
            previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            previewLayer?.bounds = bounds
            previewLayer?.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
            
            println(captureSession)
            
            captureSession.startRunning()
        }
    }
    
    public func stopRunning() {
        var err : NSError? = nil
        println("stopRunning() called")
        println(captureSession.running)
        captureSession.removeInput(previousInput)
        //        captureSession.stopRunning()
        //        captureSession.stopRunning()
        //        captureSession.startRunning()
        
        if err != nil {
            println("Error occurred on stopRunning()")
        }
    }
}