//
//  ViewController.swift
//  mTLSServer
//
//  Created by Arjun Radhakrishnan on 12/15/23.
//

import Cocoa

class ViewController: NSViewController {
    var tlsServer = TLSServer()
    override func viewDidLoad() {
        super.viewDidLoad()

        DispatchQueue.global().async {
            self.tlsServer.start()
        }
        
        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}

