//
//  ConnectViewController.swift
//  Simple Viewer
//
//

import Cocoa


class ConnectViewController : NSViewController {
    
    var completionBlock : ((Bool, String, String, String) -> Void)?
    
    @IBOutlet var passphraseField : NSTextField?
    @IBOutlet var usernameField : NSTextField?
    @IBOutlet var serverField : NSTextField?
    @IBOutlet var saveCheckbox : NSButton?
    @IBOutlet var methodButton : NSPopUpButton?
    
    @IBAction func cancel(_ sender: Any?){
        self.dismiss(nil)
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let save_settings = UserDefaults.standard.bool(forKey: "save_server")
        if save_settings {
            self.methodButton?.selectItem(at: UserDefaults.standard.integer(forKey: "auth_method"))
        }
        self.saveCheckbox?.state = save_settings ? .on :.off
        if let server = UserDefaults.standard.string(forKey: "server") {
        let query : [String : Any] = [kSecClass as String: kSecClassInternetPassword,
                                      kSecAttrServer as String: server,
                                      kSecMatchLimit as String: kSecMatchLimitOne,
                                      kSecReturnAttributes as String: true,
                                      kSecReturnData as String: true]
            var item:CFTypeRef?
            
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess {
                if let keychainItem = item as? [String : Any] {
                    serverField?.stringValue = server
                    usernameField?.stringValue = keychainItem[kSecAttrAccount as String] as? String ?? ""
                    let data = keychainItem[kSecValueData as String] as? Data
                    let passphrase = String(data: data!, encoding: .utf8)
                    passphraseField?.stringValue = passphrase!
                }
            }
        }
    }
    @IBAction func close(_ sender: Any?){
        if let passphrase = passphraseField?.stringValue, let username = usernameField?.stringValue, let servername = serverField?.stringValue {
            
            let method = methodButton?.indexOfSelectedItem
            if saveCheckbox?.state == .on {
                let query : [String : Any] =
                    [kSecClass as String: kSecClassInternetPassword,
                     kSecAttrAccount as String: username,
                     kSecAttrServer as String: servername,
                     kSecValueData as String: passphrase]
                
                SecItemAdd(query as CFDictionary, nil)
                UserDefaults.standard.setValue(true, forKey: "save_server")
                UserDefaults.standard.setValue(servername, forKey: "server")
                
                UserDefaults.standard.setValue(method == 1,  forKey:"auth_method")
            } else {
                UserDefaults.standard.removeObject(forKey: "server")
                UserDefaults.standard.setValue(false, forKey: "save_server")
            }
            completionBlock?(method ?? 0 == 1, servername, username, passphrase)
        }
        self.dismiss(nil)
    }
}
