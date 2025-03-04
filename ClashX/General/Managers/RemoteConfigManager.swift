//
//  RemoteConfigManager.swift
//  ClashX
//
//  Created by CYC on 2018/11/6.
//  Copyright © 2018 west2online. All rights reserved.
//

import Cocoa
import Alamofire

class RemoteConfigManager {
    
    var configs: [RemoteConfigModel] = []
    var refreshActivity: NSBackgroundActivityScheduler?
    
    static let shared = RemoteConfigManager()

    private init(){
        if let savedConfigs = UserDefaults.standard.object(forKey: "kRemoteConfigs") as? Data {
            let decoder = JSONDecoder()
            if let loadedConfig = try? decoder.decode([RemoteConfigModel].self, from: savedConfigs) {
                configs = loadedConfig
            } else {
                assertionFailure()
            }
        }
        migrateOldRemoteConfig()
        setupAutoUpdateTimer()
    }
    
    func saveConfigs() {
        Logger.log("Saving Remote Config Setting")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(configs) {
             UserDefaults.standard.set(encoded, forKey: "kRemoteConfigs")
        }
    }
    
    func migrateOldRemoteConfig() {
        if let url = UserDefaults.standard.string(forKey: "kRemoteConfigUrl"),
            let name = URL(string: url)?.host{
            configs.append(RemoteConfigModel(url: url, name: name))
            UserDefaults.standard.removeObject(forKey: "kRemoteConfigUrl")
            saveConfigs()
        }
    }
    
    func setupAutoUpdateTimer() {
        refreshActivity?.invalidate()
        refreshActivity = nil
        guard RemoteConfigManager.autoUpdateEnable else {
            Logger.log("autoUpdateEnable did not enable,autoUpateTimer invalidated.")
            return
        }
        Logger.log("set up autoUpateTimer")
        
        
        refreshActivity = NSBackgroundActivityScheduler(identifier: "com.ClashX.configupdate")
        refreshActivity?.repeats = true
        refreshActivity?.interval = 60 * 60 * 3 // Three hour
        refreshActivity?.tolerance = 90

        refreshActivity?.schedule() { [weak self] completionHandler in
            self?.autoUpdateCheck()
            completionHandler(NSBackgroundActivityScheduler.Result.finished)
        }
    }
    
    
    static var autoUpdateEnable:Bool {
        get {
            return UserDefaults.standard.object(forKey: "kAutoUpdateEnable") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAutoUpdateEnable")
            RemoteConfigManager.shared.setupAutoUpdateTimer()
        }
    }
    
    @objc func autoUpdateCheck() {
        guard RemoteConfigManager.autoUpdateEnable else {return}
        Logger.log("Tigger config auto update check")
        updateCheck()
    }
    
    func updateCheck(ignoreTimeLimit: Bool = false, showNotification: Bool = false) {
        let currentConfigName = ConfigManager.selectConfigName
        
        let group = DispatchGroup()
        
        for config in configs {
            if config.updating {continue}
            // 12hour check
            let timeLimitNoMantians = Date().timeIntervalSince(config.updateTime ?? Date(timeIntervalSince1970: 0)) < 60 * 60 * 12
            
            if timeLimitNoMantians && !ignoreTimeLimit {
                Logger.log("[Auto Upgrade] Bypassing \(config.name) due to time check")
                continue
            }
            Logger.log("[Auto Upgrade] Requesting \(config.name)")
            let isCurrentConfig = config.name == currentConfigName
            config.updating = true
            group.enter()
            RemoteConfigManager.updateConfig(config: config) {
                [weak config] error in
                guard let config = config else {return}
                
                config.updating = false
                group.leave()
                if error == nil {
                    config.updateTime = Date()
                }
                
                if isCurrentConfig {
                    if let error = error {
                        // Fail
                        if showNotification {
                            NSUserNotificationCenter.default
                                .post(title: NSLocalizedString("Remote Config Update Fail", comment: "") ,
                                      info: "\(config.name): \(error)")
                        }
                        
                    } else {
                        // Success
                        if showNotification {
                            let info = "\(config.name): \(NSLocalizedString("Succeed!", comment: ""))"
                            NSUserNotificationCenter.default
                                .post(title: NSLocalizedString("Remote Config Update", comment: ""), info:info)
                        }
                        NotificationCenter.default.post(name: kShouldUpDateConfig,
                                                        object: nil,
                                                        userInfo: ["notification": false])
                    }
                }
                Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
            }
        }
        
        group.notify(queue: .main) {
            [weak self] in
            self?.saveConfigs()
        }
    }
    
    
    static func getRemoteConfigData(config: RemoteConfigModel, complete:@escaping ((String?)->Void)) {
        guard var urlRequest = try? URLRequest(url: config.url, method: .get) else {
            assertionFailure()
            Logger.log("[getRemoteConfigData] url incorrect,\(config.name) \(config.url)")
            return
        }
        urlRequest.cachePolicy = .reloadIgnoringCacheData

        AF.request(urlRequest).responseString { res in
            complete(try? res.result.get())
        }
    }
    
    static func updateConfig(config: RemoteConfigModel, complete:((String?)->())?=nil) {
        getRemoteConfigData(config: config) { configString in
            guard let newConfig = configString else {
                complete?(NSLocalizedString("Download fail", comment: "") )
                return
            }
            
            let verifyRes = verifyConfig(string: newConfig)
            if let error = verifyRes {
                complete?(NSLocalizedString("Remote Config Format Error", comment: "") + ": " + error)
                return
            }
            let savePath = kConfigFolderPath.appending(config.name).appending(".yaml")

            if config.name == ConfigManager.selectConfigName {
                ConfigFileManager.shared.pauseForNextChange()
            }
            
            do {
                if FileManager.default.fileExists(atPath: savePath) {
                    try FileManager.default.removeItem(atPath: savePath)
                }
                try newConfig.write(to:  URL(fileURLWithPath: savePath), atomically: true, encoding: .utf8)
                complete?(nil)
            } catch let err {
                complete?(err.localizedDescription)
            }
        }
        
    }
    
    static func verifyConfig(string: String) -> ErrorString? {
        let res = verifyClashConfig(string.goStringBuffer())?.toString() ?? "unknown error"
        if res == "success" {
            return nil
        } else {
            Logger.log(res,level: .error)
            return res
        }
    }
}

