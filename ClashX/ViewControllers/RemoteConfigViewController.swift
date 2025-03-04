//
//  RemoteConfigViewController.swift
//  ClashX
//
//  Created by yicheng on 2019/7/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa
import RxSwift

class RemoteConfigViewController: NSViewController {

    @IBOutlet var tableView: NSTableView!
    @IBOutlet var deleteButton: NSButton!
    @IBOutlet var updateButton: NSButton!
    
    private var latestAddedConfigName: String?
    
    let disposeBag = DisposeBag()
    
    deinit {
        print("RemoteConfigViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateButtonStatus()
        
        NotificationCenter.default
            .rx.notification(Notification.Name("didGetUrl")).bind {
                [weak self] (note)  in
                guard let self = self else {return}
                guard let url = note.userInfo?["url"] as? String else {return}
                
                let name = note.userInfo?["name"] as? String
                self.showAdd(defaultUrl: url, name:name)
            }.disposed(by: disposeBag)
        
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        RemoteConfigManager.shared.saveConfigs()
    }
    
    
    // MARK: Actions

    @IBAction func actionAdd(_ sender: Any) {
        showAdd()
    }
    
    @IBAction func actionDelete(_ sender: Any) {
        RemoteConfigManager.shared.configs.safeRemove(at: tableView.selectedRow)
        tableView.reloadData()
        updateButtonStatus()
    }
    
    @IBAction func actionUpdate(_ sender: Any) {
        guard let model = RemoteConfigManager.shared.configs[safe:tableView.selectedRow] else {return}
        requestUpdate(config: model)
        tableView.reloadDataKeepingSelection()
    }
}

extension RemoteConfigViewController {
    
    func updateButtonStatus() {
        let selectIdx = tableView.selectedRow
        if selectIdx == -1 {
            deleteButton.isEnabled = false
            updateButton.isEnabled = false
            return
        }
        
        guard let config = RemoteConfigManager.shared.configs[safe:selectIdx] else {return}
        deleteButton.isEnabled = true
        updateButton.isEnabled = !config.updating
    }
    
    func showAdd(defaultUrl: String? = nil, name: String? = nil) {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Add a remote config", comment: "")
        let remoteConfigInputView = RemoteConfigAddView.createFromNib()!
        if let defaultUrl = defaultUrl {
            remoteConfigInputView.setUrl(string: defaultUrl, name: name)
        }
        alertView.accessoryView = remoteConfigInputView
        let response = alertView.runModal()
        
        guard response == .alertFirstButtonReturn else {return}
        guard remoteConfigInputView.isVaild() else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Invalid input", comment: "")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        let configName = remoteConfigInputView.getConfigName()
        let isDup = RemoteConfigManager.shared.configs.contains { $0.name == configName }
        
        guard !isDup else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("The remote config name is duplicated", comment: "")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        let remoteConfig = RemoteConfigModel(url: remoteConfigInputView.getUrlString(),
                                             name: remoteConfigInputView.getConfigName(),
                                             updateTime: nil)
        RemoteConfigManager.shared.configs.append(remoteConfig)
        latestAddedConfigName = remoteConfig.name
        requestUpdate(config: remoteConfig)
        tableView.reloadData()
        updateButtonStatus()
    }
    
    func requestUpdate(config: RemoteConfigModel) {
        guard !config.updating else {return}
        config.updating = true
        RemoteConfigManager.updateConfig(config: config) {
            [weak self, weak config] errorString in
            guard let self = self, let config = config else {return}
            config.updating = false
            if let errorString = errorString {
                let alert = NSAlert()
                alert.messageText = errorString
                alert.alertStyle = .warning
                alert.runModal()
            } else {
                config.updateTime = Date()
                RemoteConfigManager.shared.saveConfigs()
                
                if config.name == self.latestAddedConfigName {
                    ConfigManager.selectConfigName = config.name
                }
                if config.name == ConfigManager.selectConfigName {
                    NotificationCenter.default.post(Notification(name: kShouldUpDateConfig))
                }
            }
            self.tableView.reloadDataKeepingSelection()
        }
    }
}

extension RemoteConfigViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStatus()
    }
}

extension RemoteConfigViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return RemoteConfigManager.shared.configs.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        guard let config = RemoteConfigManager.shared.configs[safe:row] else {return nil}

        func setupCell(withIdentifier:String, string:String, textFieldtag:Int = 1) -> NSView? {
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: withIdentifier), owner: nil)
            if let textField = cell?.viewWithTag(1) as? NSTextField {
                textField.stringValue = string
            } else {
                assertionFailure()
            }
            
            return cell
        }
        
        switch tableColumn?.identifier.rawValue ?? "" {
        case "url":
            return setupCell(withIdentifier: "urlCell", string: config.url)
        case "configName":
            return setupCell(withIdentifier: "nameCell", string: config.name)
        case "updateTime":
            return setupCell(withIdentifier: "timeCell", string: config.displayingTimeString())

        default: assertionFailure()
        }
        return nil
    }
}



class RemoteConfigAddView: NSView, NibLoadable {
    @IBOutlet private var urlTextField: NSTextField!
    @IBOutlet private var configNameTextField: NSTextField!
    
    func getUrlString() -> String {
        return urlTextField.stringValue
    }
    
    func getConfigName() -> String {
        if configNameTextField.stringValue.count > 0 {
            return configNameTextField.stringValue
        }
        return configNameTextField.placeholderString ?? ""
    }
    
    func isVaild() -> Bool {
        return urlTextField.stringValue.isUrlVaild() && getConfigName().count > 0
    }
    
    func setUrl(string: String, name: String?) {
        urlTextField.stringValue = string
        if let name = name, name.count > 0 {
            configNameTextField.placeholderString = name
        } else {
            updateConfigName()
        }
    }
    
    private func updateConfigName() {
        guard urlTextField.stringValue.isUrlVaild() else {return}
        let urlString = urlTextField.stringValue
        configNameTextField.placeholderString = URL(string: urlString)?.host ?? "unknown"
    }
    
}

extension RemoteConfigAddView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateConfigName()
    }
}

