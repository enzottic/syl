//
//  UserDefaults+SageColor.swift
//  FinanceTracker
//
//  Created by Enzo on 10/6/25.
//

import SwiftUI

public extension UserDefaults {
    func sageColor(forKey key: String) -> Color? {
        guard let components = array(forKey: key) as? [Double], components.count == 4 else { return nil }
        return Color(.sRGB, red: components[0], green: components[1], blue: components[2], opacity: components[3])
    }

    func setSageColor(_ color: Color, forKey key: String) {
        let resolved = color.resolve(in: EnvironmentValues())
        set([Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity)], forKey: key)
    }
}

