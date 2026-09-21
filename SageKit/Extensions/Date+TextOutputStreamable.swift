//
//  Date+TextOutputStreamable.swift
//  FinanceTracker
//
//  Created by Enzo on 1/10/26.
//
import Foundation

extension Date: @retroactive TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        target.write(self.ISO8601Format())
    }
}
