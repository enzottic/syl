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
public typealias Expense = SageSchemaV9.Expense
public typealias ExpenseTag = SageSchemaV9.ExpenseTag
public typealias RecurringExpenseRule = SageSchemaV9.RecurringExpenseRule
public typealias RecurrenceFrequency = SageSchemaV9.RecurrenceFrequency
public typealias ExpenseAccount = SageSchemaV9.ExpenseAccount
