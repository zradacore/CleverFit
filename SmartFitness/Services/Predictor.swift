//
//  Predictor.swift
//  SmartFitness
//
//  Created by Владимир Никитин on 22.10.2022.
//

import Foundation
import Vision

typealias ThrowingClassifier = PlankaModel3

class Predictor{
    
    weak var delegate : PredictorDelegate?
    
    let predictorWindowSize = 30
    var posesWindow: [VNHumanBodyPoseObservation] = []
    
    init(){
        posesWindow.reserveCapacity(predictorWindowSize)
    }
    
    func estimation(sampleBuffer: CMSampleBuffer){
        let requestHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer,
                                                   orientation: .up)
        
        let request = VNDetectHumanBodyPoseRequest(completionHandler: bodyPoseHandler)
        do {
            try requestHandler.perform([request])
        } catch  {
            print("Unable to perform the request, with error \(error)")
        }
    }
    
    func bodyPoseHandler(request : VNRequest, error: Error?){
        guard let observations = request.results as? [VNHumanBodyPoseObservation] else {return}
        observations.forEach {
            processObservation($0)
        }
        if let result = observations.first {
            storeObservation(result)
            labelActionType()
        }
    }
    
    func labelActionType(){
        guard let throwingClassifier = try? ThrowingClassifier(configuration: MLModelConfiguration()),
        let poseMultiArray = prepareInputWithObservation(posesWindow),
        let predictions = try? throwingClassifier.prediction(poses: poseMultiArray)
        else {return}
        
        let label = predictions.label
        let confidence = predictions.labelProbabilities[label] ?? 0
        delegate?.predictor(self, didLabelAction: label, with: confidence)
    }
    
    func prepareInputWithObservation(_ observations: [VNHumanBodyPoseObservation]) -> MLMultiArray?{
        let numAvailableFrames = observations.count
        let observationsNeeded = 30
        var multiArrayBuffer = [MLMultiArray]()
        
        for frameIndex in 0..<min(numAvailableFrames, observationsNeeded){
            let pose = observations[frameIndex]
            do {
                let oneFrameMultiArray = try pose.keypointsMultiArray()
                multiArrayBuffer.append(oneFrameMultiArray)
            } catch {
                continue
            }
        }
        if numAvailableFrames < observationsNeeded{
            for _ in 0..<(observationsNeeded - numAvailableFrames){
                do{
                    let oneFrameMultiArray = try MLMultiArray(shape: [1, 3, 18], dataType: .double)
                    try resetMultiArray(oneFrameMultiArray)
                    multiArrayBuffer.append(oneFrameMultiArray)
                }catch{
                    continue
                }
            }
        }
        return MLMultiArray(concatenating: [MLMultiArray](multiArrayBuffer), axis: 0, dataType: .float)
    }
    
    func resetMultiArray(_ predictionWindow: MLMultiArray,with value: Double = 0.0) throws{
        let pointer = try UnsafeMutableBufferPointer<Double>(predictionWindow)
        pointer.initialize(repeating: value)
    }
    
    func storeObservation(_ observation : VNHumanBodyPoseObservation){
        if posesWindow.count >= predictorWindowSize{
            posesWindow.removeFirst()
        }
        
        posesWindow.append(observation)
    }
    
    func processObservation(_ observation: VNHumanBodyPoseObservation){
        do{
            let recognizedPoints = try observation.recognizedPoints(forGroupKey: .all)
            let displayedPoints = recognizedPoints.map {
                CGPoint(x: $0.value.x, y: 1 - $0.value.y)
            }
            delegate?.predictor(self, didFindNewRecognizedPoints: displayedPoints)
        }catch{
            print("error finding recognized points")
        }
    }
}
