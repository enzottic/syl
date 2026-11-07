//
//  SageSchema.swift
//  FinanceTracker
//
//  Created by Enzo on 3/7/26.
//
import SwiftData
import Foundation
import SwiftUI

// The current schema version. Point these at the newest SageSchemaV* when adding one,
// and append it to SageSchemaMigrationPlan.
public typealias Expense = SageSchemaV10.Expense
public typealias ExpenseTag = SageSchemaV10.ExpenseTag
public typealias RecurringExpenseRule = SageSchemaV10.RecurringExpenseRule
public typealias RecurrenceFrequency = SageSchemaV10.RecurrenceFrequency
public typealias ExpenseAccount = SageSchemaV10.ExpenseAccount
