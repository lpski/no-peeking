//
//  CaptureMonitor.swift
//  NoPeeking
//
//  Created by Luke Porupski on 12/17/20.
//  Copyright © 2020 Golden Chopper. All rights reserved.
//

import AppKit
import Vision
import AVKit

protocol CaptureMonitorDelegate {
    func faceDetectionUpdate(faces: [VNFaceObservation])
    func captureError(error: Error)
    func cameraAccessRejected()
}

class CaptureMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var delegate: CaptureMonitorDelegate
    var lastPeepingCount: Int = 0
    
    // AVCapture variables to hold sequence data
    private var session: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var videoDataOutputQueue: DispatchQueue?
    private var captureDevice: AVCaptureDevice?
    private var captureDeviceResolution: CGSize = CGSize()
    
    // Vision requests
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    
    init(delegate: CaptureMonitorDelegate) {
        self.delegate = delegate
        super.init()
        
        self.session = self.setupAVCaptureSession()
        self.session?.startRunning()
    }
    
    func pause() {
        self.session?.stopRunning()
    }
    
    func start() {
        self.session?.startRunning()
    }
    
    func restart() {
        self.session = self.setupAVCaptureSession()
        self.session?.startRunning()
    }
    
    
    
    
    
    // MARK: AVCapture Setup
    
    /// - Tag: CreateCaptureSession
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        do {
            let inputDevice = try self.configureFrontCamera(for: captureSession)
            self.configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            return captureSession
        } catch let executionError as NSError {
            print("execution error:", executionError)
            delegate.cameraAccessRejected()
        } catch {
            print("unexpected error")
        }
        
        self.teardownAVCapture()
        
        return nil
    }
    
    /// - Tag: ConfigureDeviceResolution
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
//            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
//            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        
        throw NSError(domain: "CaptureMonitor", code: 1, userInfo: nil)
    }
    
    /// - Tag: CreateSerialDispatchQueue
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
        // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
        let videoDataOutputQueue = DispatchQueue(label: "com.pekul.no-peeking")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)

        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        videoDataOutput.connection(with: .video)?.isEnabled = true

        self.videoDataOutput = videoDataOutput
        self.videoDataOutputQueue = videoDataOutputQueue

        self.captureDevice = inputDevice
        self.captureDeviceResolution = resolution
    }
    
    
    // Removes infrastructure for AVCapture as part of cleanup.
    fileprivate func teardownAVCapture() {
        self.videoDataOutput = nil
        self.videoDataOutputQueue = nil
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // MARK: Performing Vision Requests
    
    enum Quadrant {
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
    }
    
    // Top/Bottom not yet accurate but Right/Left is
    fileprivate func determinePupilQuadrant(eyeCenter: CGPoint, pupil: CGPoint) -> Quadrant {
        if (pupil.x < eyeCenter.x) {
            return pupil.y > eyeCenter.y ? .topLeft : .bottomLeft
        } else {
            return pupil.y > eyeCenter.y ? .topRight : .bottomRight
        }
    }
    
    // Handle delegate method callback on receiving a sample buffer.
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]

        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
        
        // Extract and format pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: pixelBuffer, options: nil).oriented(.upMirrored)
        
        
        let faceLandmarks = VNDetectFaceLandmarksRequest()
        let faceLandmarksDetectionRequest = VNSequenceRequestHandler()
        try? faceLandmarksDetectionRequest.perform([faceLandmarks], on: ciImage)
        
        print("Detected:", faceLandmarks.results?.count, "faces")
        if let results = faceLandmarks.results as? [VNFaceObservation] {
            var peeping = results.filter({ face in
                // Ensure high confidence that detected object is indeed a face
                guard face.confidence >= 0.3 else { return false }
                
                // Ensure yaw & roll indicate face is in general direction of screen
                let rollAngle = ((face.roll ?? 0) as! Double) * 180.0 / .pi // 30 deg increments
                let yawAngle = ((face.yaw ?? 0) as! Double) * 180.0 / .pi // 45 deg increments
                guard rollAngle.rounded().magnitude < 31 && yawAngle.rounded().magnitude < 46 else { return false }
                
                let leftEye = face.landmarks?.leftEye?.normalizedPoints
                let rightEye = face.landmarks?.rightEye?.normalizedPoints
                let leftPupil = face.landmarks?.leftPupil?.normalizedPoints
                let rightPupil = face.landmarks?.rightPupil?.normalizedPoints
                
                
                func getRange(vals: [CGPoint]?) -> (min: CGPoint, max: CGPoint, center: CGPoint, width: CGFloat)? {
                    guard let pts = vals else { return nil }

                    let descX = pts.sorted(by: { (l, r) in r.x <= l.x }).map({ pt in pt.x })
                    let descY = pts.sorted(by: { (l, r) in r.y <= l.y }).map({ pt in pt.y })
                    
                    let max = CGPoint(x: descX.first ?? 0, y: descY.first ?? 0)
                    let min = CGPoint(x: descX.last ?? 0, y: descY.last ?? 0)
                    let width = sqrt(pow(max.x - min.x, 2) + pow(max.y - min.y, 2))
                    
                    let summed: (CGFloat, CGFloat) = vals!.reduce((0, 0), { (res, pt) in
                        return (res.0 + pt.x, res.1 + pt.y)
                    })
                    let center = CGPoint(x: (summed.0 / CGFloat(pts.count)), y: (summed.1 / CGFloat(pts.count)))
                    
                    return (min, max, center, width)
                }
                
                
                // Obtain eye widths
                guard let leftData = getRange(vals: leftEye), let rightData = getRange(vals: rightEye) else {
                    return false
                }
                
                // Indicates how far left or right a face is pointed, similar to yaw
                let eyeWidthDiff = ((leftData.width - rightData.width).magnitude / (leftData.width + rightData.width)) * 100
                let highOffsetPercentThreshold: CGFloat = 10
                let hasHighOffset = eyeWidthDiff >= highOffsetPercentThreshold
                
                let lookingRight = leftData.width > rightData.width
                guard let lp = leftPupil, let rp = rightPupil else { return false }
                
                let data = lookingRight ? leftData : rightData
                let pupil = lookingRight ? lp[0] : rp[0]
                let pupilQuadrant = determinePupilQuadrant(eyeCenter: data.center, pupil: pupil)
                let pupilXOffsetPercent = ((pupil.x - data.center.x).magnitude / (data.width / 2)) * 100

//                print("pupil quadrant:", pupilQuadrant)
//                print("pupil offset %:", pupilXOffsetPercent.rounded(), "%")
//                print("eye offset %:", eyeWidthDiff.rounded(), "%\n")
//                print("mid line:", face.landmarks?.faceContour?.normalizedPoints.area())
                
                if (lookingRight) {
                    let highPupilOffset = pupilXOffsetPercent > 15 && pupil.x > data.center.x
                    return !highPupilOffset && !(hasHighOffset && (pupilQuadrant == .topRight || pupilQuadrant == .bottomRight))
                } else {
                    let highPupilOffset = pupilXOffsetPercent > 15 && pupil.x < data.center.x
                    return !highPupilOffset && !(hasHighOffset && (pupilQuadrant == .bottomLeft || pupilQuadrant == .topLeft))
                }
            })
            
            print(peeping.count, "faces looking at screen\n\n")
            
            if peeping.count == 1 {
                peeping = []
            } else if (peeping.count > 1) {
                // Primary user has lowest area for face, sort by desc order of area and remove smallest
                peeping.sort(by: {(l, r) in
                    guard let lPoints = l.landmarks?.allPoints, let rPoints = r.landmarks?.allPoints else {
                        return false
                    }
                    return rPoints.normalizedPoints.area() <= lPoints.normalizedPoints.area()
                })
                let _ = peeping.popLast()
            }

            if (self.lastPeepingCount != peeping.count) {
                self.lastPeepingCount = peeping.count
                self.delegate.faceDetectionUpdate(faces: peeping)
            }
        }
    }
    
}

extension Array where Element == CGPoint {
    func area() -> CGFloat {
        let n = self.count
        var area: CGFloat = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            area += self[i].x * self[j].y
            area -= self[j].x * self[i].y
            
        }
        return area.magnitude / 2
    }
}

