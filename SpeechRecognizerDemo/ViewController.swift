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
    case IntermittentError // Temporary, resolvable error
}

class ViewController: UIViewController, SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate {
    private let (recordEmoji, stopEmoji, errorEmoji) = ("⏺", "⏹", "🚫")
    
    /*
      The recognizer uses the device's locale if one isn't specified.
      Example: SFSpeechRecognizer(locale: Locale(localeIdentifier: "en-US"))
      Get a set of locales with SFSpeechRecognizer.supportedLocales()
    */
    private let recognizer = SFSpeechRecognizer()!
    // Used to create our request
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    // Used to hold a reference to that request
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Used to access our microphone buffer
    private let audioEngine = AVAudioEngine()
    
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var outputView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // We no longer disable the record button on load.
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
                    self.respondToStatus(aStatus)
                }
            }
        } else {
            respondToStatus(status)
        }
    }
    
    // This is used exclusively by startTranscription (further nesting would be really hard to read).
    private func respondToStatus(_ status: SFSpeechRecognizerAuthorizationStatus) {
        // Nested function to access microphone audio buffer and start a speech recognition request.
        func performRequest() throws {
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
            
            guard let recognitionRequest = recognitionRequest else { throw SimpleAudioInputError.IntermittentError }
            recognitionRequest.contextualStrings = ["Framdandy, Hullabalaa, Blamp"]
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
        
        switch status {
        case .authorized: // We're good to go
            self.recordButton.isEnabled = true
            do {
                try performRequest()
            } catch SimpleAudioInputError.IntermittentError {
                self.handleIntermittentError()
            } catch {
                // HardwareIncompatibility error or something more surprising.
                // This is a major problem for this app.
                self.handleSeriousError()
            }
        case .denied, .restricted:
            self.handleSeriousError()
        default:
            break
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
    
    func handleSeriousError() {
        outputView.textAlignment = .center
        outputView.font = UIFont.systemFont(ofSize: 300)
        outputView.text = errorEmoji
        recordButton.isHidden = true
        // ...or fatalError("Some boring message...")
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
    
    // MARK: SFSpeechRecognizerDelegate
    
    // You can also check 'recognizer.isAvailable' at any time
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
    
    /*
     We'll use this to display transcriptions in real time as they come in.
     Called for all recognitions, including non-final hypotheses.
     Transcriptions may be changed as the recognizer gets more information/context.
    */
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        print("Hypothesis transcription: \(transcription)")
        outputView.text = transcription.formattedString
    }
    
    /*
     Called only for final recognitions of utterances. No more about the utterance will be reported.
     That's what the documentation says, anyway. Actually this is called once when the task ends.
    */
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        print("Final result: \(recognitionResult)")

        let bestTranscriptionSegments = recognitionResult.bestTranscription.segments
        
        self.outputView.attributedText = attributedStringForSegments(bestTranscriptionSegments)
    }
    
    // Called when the task is no longer accepting new audio but may be finishing final processing
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        // Show "temporarily disabled" state for record button.
        recordButton.isEnabled = false
        recordButton.setTitle("...", for: .disabled)
    }
    
    /*
     Called when recognition of an utterances is finished.
     If 'successfully' is false, the 'error' property of the task will contain error information
     We'll use this method to stop listening to the microphone and reset our UI for another request.
    */
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        print("Task did finish successfully: \(successfully)")
        if (!successfully) {
            print("Error: \(task.error)")
        }
        
        audioEngine.stop()
        
        let inputNode = audioEngine.inputNode
        
        inputNode!.removeTap(onBus: 0)
        
        recognitionRequest = nil
        recognitionTask = nil
        
        recordButton.isEnabled = true
        recordButton.setTitle(recordEmoji, for: []) // Set title for all states
    }
    
    // MARK: UI Customizations
    
    func attributedStringForSegments(_ segments: [SFTranscriptionSegment], defaultStyle: Bool = true) -> AttributedString {
        
        let output = NSMutableAttributedString()
        
        for (index, segment) in segments.enumerated() {
            var outputPartial = NSMutableAttributedString()
            
            // Set darkness based on segment confidence
            // Greener indicates higher confidence
            let greenLevel = Float(segment.confidence)
            let color = UIColor.init(colorLiteralRed: 1.0 - greenLevel, green: greenLevel, blue: 0.0, alpha: 1.0)
            
            // Simulate drifting attention (timestamp affects font size)
            var fontSize = 20.0
            if (segment.timestamp > 10.0) {
                fontSize = 200.0 / segment.timestamp
            }
            let attributes = [
                NSForegroundColorAttributeName: color,
                NSFontAttributeName: UIFont.systemFont(ofSize:CGFloat(fontSize))
            ]
            
            // Build segment and show alternates guesses in parenthesis (same font size, to be lazy)
            var segmentText = segment.substring
            let alternates = segment.alternativeSubstrings
            if alternates.count > 0 {
                segmentText += " (\(alternates.joined(separator: ",")))"
            }
            outputPartial = NSMutableAttributedString(string: segmentText, attributes: attributes)
            
            // Visualize a crude guess about the pauses between words.
            // I'm leaving improvements as an exercise for the reader.
            var spacerFontSize: Double
            var spacer: NSMutableAttributedString
            
            if index == 0 {
                // Pause between start of word and first segment.
                spacerFontSize = segment.timestamp * 5.0
            } else {
                // Make a very rough guess about time spent speaking a word.
                // Assume all words take 0.5 seconds to say.
                spacerFontSize = (segment.duration - 0.5) * 5.0
            }
            
            if (spacerFontSize < 0.0) {
                spacerFontSize = 0.0
            }
            spacerFontSize += 20.0
            
            spacer = NSMutableAttributedString(string: " ", attributes: [NSFontAttributeName: UIFont.systemFont(ofSize:CGFloat(spacerFontSize))])
    
            if index == 0 {
                 // Prepend spacer for start delay
                outputPartial.insert(spacer, at: 0)
            } else {
                outputPartial.append(spacer)
            }
            
            // Add segment to output
            output.append(outputPartial)
        }
        
        return output
    }
    
    /*
     This is necessary because textViews automatically change their default style
     to match the first character of any attributed text you add to it.
    */
    func resetTextViewStyle() {
        outputView.text = nil;
        outputView.font = nil;
        outputView.textColor = nil;
    }
}

   
