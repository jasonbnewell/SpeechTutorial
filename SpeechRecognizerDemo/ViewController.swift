//
//  ViewController.swift
//  SpeechRecognizerDemo
//
//  Created by Jason Newell on 7/16/16.
//  Copyright © 2016 jbn. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    let (playEmojii, stopEmojii) = ("⏺", "⏹")
    
    @IBOutlet weak var outputView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction func recordPressed(_ sender: AnyObject) {
    }
}

   
