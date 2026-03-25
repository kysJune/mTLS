//
//  ViewController.swift
//  mTLSClient
//
//  Created by Arjun Radhakrishnan on 12/18/23.
//

import Cocoa
import Network

class ViewController: NSViewController {
    
    
    @IBOutlet weak var sendTextFeild: NSTextField?
    @IBOutlet weak var recvdLabel: NSTextField?
    @IBOutlet weak var hostTextFeild: NSTextField?
    @IBOutlet weak var portTextFeild: NSTextField?
    @IBOutlet weak var connectButton: NSButton?
    @IBOutlet weak var sendButton: NSButton?
    
    enum Status {
        case invalid
        case ready
        case connecting
        case connected
        case disconnecting
        case disconnected
    }
    
    var state : Status = .invalid {
        didSet {
            
            switch(state) {
                
            case .invalid:
                self.connectButton?.isEnabled = false
                self.connectButton?.title = "Connect"
                self.sendButton?.isEnabled = false
                
            case .ready:
                self.connectButton?.isEnabled = true
                self.connectButton?.title = "Connect"
                self.sendButton?.isEnabled = false
                self.sendTextFeild?.stringValue = ""
                self.recvdLabel?.stringValue = ""
            case .connecting:
                self.connectButton?.isEnabled = false
                self.connectButton?.title = "..."
                self.sendButton?.isEnabled = false
                self.sendTextFeild?.stringValue = ""
                self.recvdLabel?.stringValue = ""
                
            case .connected:
                self.connectButton?.title = "Disconnect"
                self.sendButton?.isEnabled = true
                self.connectButton?.isEnabled = true
                
            case .disconnecting:
                self.connectButton?.isEnabled = false
                self.connectButton?.title = "..."
                self.sendButton?.isEnabled = false
                self.sendTextFeild?.stringValue = ""
                self.recvdLabel?.stringValue = ""
                
            case .disconnected:
                self.connectButton?.isEnabled = true
                self.connectButton?.title = "Connect"
                self.sendButton?.isEnabled = false
                self.sendTextFeild?.stringValue = ""
                self.recvdLabel?.stringValue = ""
            }
        }
    }
    
    var identityProvider: IdentityProvider!
    var nwClient: Client?
    var host: String?
    var port: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        identityProvider = IdentityProvider()
        guard identityProvider.loadIdentities() > 0 else {
            return
        }
        
        self.state = .invalid
        nwClient = Client(self);
        nwClient?.setIdentityProvider(identityProvider)
        self.state = .ready
    }
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func send(_ sender: Any?) {
        guard state == .connected else {
            print("Can't send as not connected")
            return
        }
        
        guard let msg = self.sendTextFeild?.stringValue, !msg.isEmpty else {
            print("Empty message cant send")
            return
        }
        
        guard let data = msg.data(using: .utf8), !data.isEmpty else {
            print("Cannot convert string to data")
            return
        }
        
        self.nwClient?.send(data)
    }
    
    
    @IBAction func connectDisconnect(_ sender: Any?) {
        
        if state == .ready || state == .disconnected {
            //connect
            guard let host  = self.hostTextFeild?.stringValue, !host.isEmpty,
                  let port = self.portTextFeild?.stringValue, !port.isEmpty else {
                print("Cannot connect host/port empty")
                return
            }
            
            self.nwClient?.connect(to: host, andPort: port)
            state = .connecting
        }
        
        if state == .connected {
            self.nwClient?.stop()
            state = .disconnecting
        }
        
    }
}

extension ViewController: ClientDelegate {
    func didConnect(_ client: Client) {
        print("Did connect nwclient")
        DispatchQueue.main.async {
            self.state = .connected
        }
    }
    
    func didDisconnect(_ client: Client, withError error: Error?) {
        print("Did disonnect nwclient")
        DispatchQueue.main.async {
            self.state = .disconnected
        }
    }
    
    func didReceive(_ data: Data, from client: Client) {
        
        guard self.state == .connected else {
            print("Received msg from server but not connect")
            return
        }
        
        guard !data.isEmpty,
              let str = String(data: data, encoding: .utf8) else {
            print("Received msg from server but not cannot convert to string")
            return
        }
        
        DispatchQueue.main.async {
            self.recvdLabel?.stringValue = str
        }
    }
}
