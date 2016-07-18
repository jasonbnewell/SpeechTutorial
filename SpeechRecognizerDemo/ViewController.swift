//
//  ViewController.swift
//  SpeechRecognizerDemo
//
//  Created by Jason Newell on 7/16/16.
//  Copyright © 2016 jbn. All rights reserved.
//

import UIKit
import Speech

enum SimpleAudioInputError: ErrorProtocol {
    case HardwareIncompatability // Fundamental problem accessing audio input
    case IntermittentError // Resolvable
}

class ViewController: UIViewController, SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate {
    private let (recordEmoji, stopEmoji, errorEmoji) = ("⏺", "⏹", "💩")
    
    private let recognizer = SFSpeechRecognizer()! // Initialize with device locale
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioEngine = AVAudioEngine()
    
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var outputView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        recognizer.delegate = self
    }
    
    // MARK: Recording and Transcription
    
    // This method checks/requests authorization, then handles errors or starts transcription
    func startTranscription() {
        let status = SFSpeechRecognizer.authorizationStatus()
        
        // Have we already requested authorization?
        if status == .notDetermined { // We have not.
            SFSpeechRecognizer.requestAuthorization { (aStatus) in
                // This might not be called on the main thread.
                // Perform on main queue to update UI.
                OperationQueue.main().addOperation {
                    self._respondToStatus(aStatus)
                }
            }
        } else {
            _respondToStatus(status)
        }
    }
    
    
    // This is used exclusively by startTranscription.
    private func _respondToStatus(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .authorized: // We're good to go
            self.recordButton.isEnabled = true
            do {
                try _performRequest()
            } catch SimpleAudioInputError.IntermittentError {
                self.handleIntermittentError()
            } catch {
                // HardwareIncompatibility error or something more surprising.
                // This is a major problem for this app.
                self.handleSTBError()
            }
        case .denied, .restricted:
            self.handleSTBError()
        default:
            break
        }
    }
    
    // This is used exclusively by _respondToStatus (it could be doubly nested if that wasn't so hard to read).
    // Access microphone audio buffer and start a speech recognition request.
    func _performRequest() throws {
        // Perform transcription after receiving authorized status
        let recordSession = AVAudioSession.sharedInstance()
        
        do {
            try recordSession.setCategory(AVAudioSessionCategoryRecord)
            try recordSession.setMode(AVAudioSessionModeMeasurement)
        } catch {
            // Note: This may actually be impossible to reach on iOS devices.
            throw SimpleAudioInputError.HardwareIncompatability
        }
        try! recordSession.setActive(true, with: .notifyOthersOnDeactivation)
        
        // Cancel the previous task if it's running.
        if (recognitionTask?.isCancelled) != nil {
            recognitionTask!.cancel()
        }
        
        // Create a speech recognition request using an audio buffer
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // Couldn't create request for one reason or another (e.g. connectivity problem).
        guard let recognitionRequest = recognitionRequest else { throw SimpleAudioInputError.IntermittentError }
        
        // Automatically segment final results by word
//        recognitionRequest.detectMultipleUtterances = true
        // Add your own custom words. This works way better than it should.
        recognitionRequest.contextualStrings = ["Framdandy, Hullabalaa, Blamp, Phraternity"]
        // Other options include "confirmation" (e.g. yes, no - short responses) and "search" (for search requests.
        recognitionRequest.taskHint = .dictation
        
        guard let inputNode = audioEngine.inputNode else { throw SimpleAudioInputError.HardwareIncompatability }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        // Keep a reference to the task so that we can cancel it.
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest, delegate: self)
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            // This could be a caused by a more permanent problem, but we've made it this far...
            throw SimpleAudioInputError.IntermittentError
        }
        
        outputView.text = "..."
    }
    
    // MARK: IBAction
    
    @IBAction func recordPressed(_ sender: AnyObject) {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recordButton.isEnabled = false
            // Stopping, will reset title when request finalizes.
            recordButton.setTitle("...", for: .disabled)
        } else {
            // Ask for permission and start transcription
            startTranscription()
            recordButton.setTitle(stopEmoji, for: [])
        }
    }
    
    // MARK: Update UI for Errors
    
    func handleIntermittentError() {
        // Temporarily disable button, pulse output red to indicate problem
        self.recordButton.isEnabled = false
        
        UIView.animateKeyframes(withDuration: 1.0, delay: 0.0, options:[], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.2, animations: {
                self.outputView.backgroundColor = UIColor.red()
            })
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8, animations: {
                self.outputView.backgroundColor = UIColor.clear()
            })
            }, completion: { (finished) in
                self.recordButton.isEnabled = true
        })
    }
    
    func handleSTBError() {
        outputView.textAlignment = .center
        outputView.font = UIFont.systemFont(ofSize: 300)
        outputView.text = errorEmoji
        recordButton.isHidden = true
        // ...or fatalError("Some boring message...")
    }
    
    // MARK: SFSpeechRecognizerDelegate
    
    // You can also  check 'recognizer.isAvailable' at any time.
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle(recordEmoji, for: [])
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle(errorEmoji, for: .disabled)
        }
    }

    // MARK: SFSpeechRecognitionTaskDelegate
    
    // Called for all recognitions, including non-final hypotheses.
    // Use this to get transcriptions as they come in (realtime). 
    // Transcriptions may be changed as the recognizer gets more context.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        
        let segments = transcription.segments
        let lastSegment = segments[segments.count - 1]
        // Console output
        print("Hypothesized segment: \(lastSegment)")
        print("Alternative guesses: \(lastSegment.alternativeSubstrings)")
        
        outputView.text = transcription.formattedString
    }
    
    // Called only for final recognitions of utterances. No more about the utterance will be reported.
    // That's what the documentation says, anyway. Actually this is called once when the task ends.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        print("Best final result: \(recognitionResult.transcriptions)")

        let outputText = NSMutableAttributedString(string: "")
        
        recognitionResult.bestTranscription.segments.forEach { (segment) in
            outputText.append(formatSegment(segment))
            
            print(segment)
            print("Final segment: \(segment.substring)")
            print("Other suggestions: \(segment.alternativeSubstrings)")
        }
        
        print(outputText)
//
        self.outputView.attributedText = outputText
    }
    
    // Called when the task is no longer accepting new audio but may be finishing final processing
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        // Show "temporarily disabled" state for record button.
        recordButton.isEnabled = false
        recordButton.setTitle("...", for: .disabled)
    }
    
    // Called when recognition of all requested utterances is finished.
    // If successfully is false, the error property of the task will contain error information
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        print(task.error)
        audioEngine.stop()
        
        let inputNode = audioEngine.inputNode
        
        inputNode!.removeTap(onBus: 0)
        
        recognitionRequest = nil
        recognitionTask = nil
        
        recordButton.isEnabled = true
        recordButton.setTitle(recordEmoji, for: []) // Set title for all states
    }
    
    // MARK: UI Customizations
    
    func formatSegment(_ segment: SFTranscriptionSegment, defaultStyle: Bool = true) -> AttributedString {
        // Set darkness based on segment confidence
        print(CGFloat(segment.confidence))
        print(segment)
        
        let level = Float(segment.confidence * segment.confidence)
        // Darker is more confident
        let color = UIColor.init(colorLiteralRed: level, green: level, blue: level, alpha: 1.0)
        // Larger means longer duration
        let fontSize =  CGFloat(segment.duration * 10.0)
        let attributes = [
            NSForegroundColorAttributeName: color,
            NSFontAttributeName: UIFont.systemFont(ofSize:fontSize)
        ]
        
        var durationSpacing = ""
        _ = segment.duration
        
        durationSpacing.append(" ")
        
        
        return AttributedString(string: durationSpacing.appending(segment.substring.appending(durationSpacing)) attributes: attributes))
        
    }
    
    // Reset the output view
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        let attributes = [
            NSForegroundColorAttributeName: UIColor.black(),
            NSFontAttributeName: UIFont.systemFont(ofSize:12)
        ]
        outputView.attributedText = NSMutableAttributedString(string: "", attributes: attributes)
    }
}

   
