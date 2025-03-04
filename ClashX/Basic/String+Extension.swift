//
//  String+Extension.swift
//  ClashX
//
//  Created by yicheng on 2018/10/7.
//  Copyright © 2018年 west2online. All rights reserved.
//
import Foundation

extension String
{
    func trimed() -> String {
        let whitespaces = CharacterSet(charactersIn: " \n\r\t")
        return self.trimmingCharacters(in: whitespaces)
    }
    
    func isUrlVaild() -> Bool {
        guard let url = URL(string: self) else {return false}
        
        guard url.host != nil,
            let scheme = url.scheme else {
                return false
        }
        return ["http","https"].contains(scheme)
    }

}
