//
//  ExpenseTag.swift
//  FinanceTracker
//
//  Created by Enzo on 10/7/25.
//
import SwiftUI
import SwiftData
import UIKit

@objc(UIColorValueTransformer)
public final class UIColorValueTransformer: ValueTransformer {
    
    public override func transformedValue(_ value: Any?) -> Any? {
        guard let color = value as? UIColor else { return nil }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
            return data
        } catch {
            assertionFailure("Failed to transform `UIColor` to `Data`")
            return nil
        }
    }
    
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? NSData else { return nil }
        
        do {
            let color = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data as Data)
            return color
        } catch {
            assertionFailure("Failed to transform `Data` to `UIColor`")
            return nil
        }
    }
    
    public override class func transformedValueClass() -> AnyClass {
        return UIColor.self
    }
    
    public override class func allowsReverseTransformation() -> Bool {
        return true
    }
}

public extension UIColorValueTransformer {
    static let name = NSValueTransformerName(rawValue: String(describing: UIColorValueTransformer.self))
    
    static nonisolated func register() {
        let transformer = UIColorValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}
