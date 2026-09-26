//
//  ReceiptParserService.swift
//  FinanceTracker
//
//  Created by Enzo on 5/21/26.
//
import Foundation
import UIKit
import Vision
import FoundationModels
import SageKit

@available(iOS 26.0, *)
class ReceiptParserService {
    init() {}

    func parseReceipt(image: UIImage, tags: [ExpenseTag]) async throws -> ParsedExpense {
        guard SystemLanguageModel.default.isAvailable else {
            throw ReceiptParserError.languageModelUnavailable
        }

#if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return try await parseReceiptMultimodal(image: image, tags: tags)
        }
#endif
        
        let text = try await recognizeTextInImage(image: image)
        return try await extractExpenseDataFromText(receiptText: text, tags: tags)
    }
    
#if compiler(>=6.4)
    @available(iOS 27.0, *)
    private func parseReceiptMultimodal(image: UIImage, tags: [ExpenseTag]) async throws -> ParsedExpense {
        let session = LanguageModelSession()
        
        do {
            let response = try await session.respond(
                generating: ParsedExpense.self
            ) {
                """
                You are an experienced expense categorizer. Attached is an image of a receipt. The image might be a real picture of a physical receipt, or a screenshot of an order confirmation. You are to determine the following information from the image:
                1. The total price of the item purchased (MOST IMPORTANT)
                2. The name of what was purchased. For example, if you see a grocery receipt, you would note "Groceries". If you see a receipt for a TV, you would say "TV". The name of the store would suffice as well if you cannot determine the exact item or if there are multiple items. Try to be as specific as possible. For example, if you see the name of the specific TV that was purchased, use that instead.
                3. The category of what this item/purchase would generally be. There are only two options: Needs or Wants. Needs describe expenses that are needed/must be spent. This includes rent, groceries, utility bills, and other payments. Wants are not needed and are leisure spends, such as new devices, eating out, shopping, and clothes. Pick the best option for the receipt.
                4. The date the transaction occurred on. If no date is found, do NOT provide a date.
                5. A tag that further describes the expense. You MUST pick EXACTLY ONE tag ONLY from the provided list. If no tag matches, do not provide a tag.
                
                If you've determined the provided image is not of a receipt, set the isReceipt flag to false, and provide dummy values for the rest of the fields.
                
                List of Available Tags: \(tags.compactMap { $0.name }.joined(separator: ","))
                """
                Attachment(image)
            }
            
            guard response.content.isReceipt == true  else {
                throw ReceiptParserError.noReceipt
            }
            
            return response.content
        } catch {
            throw ReceiptParserError.parsingFailed
        }
    }
#endif

    // Uses the Vision framework to pull text out of the image
    private func recognizeTextInImage(image: UIImage) async throws -> String {
        guard let imageData = image.pngData() else {
            throw ReceiptParserError.imageEncodingFailed
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate

        let results: [RecognizedTextObservation]
        do {
            results = try await request.perform(on: imageData)
        } catch {
            throw ReceiptParserError.textRecognitionFailed
        }

        let text = results.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ReceiptParserError.noTextFound
        }

        return text
    }

    // Uses a local AI model to generate an expense from the recognized receipt text.
    private func extractExpenseDataFromText(receiptText: String, tags: [ExpenseTag]) async throws -> ParsedExpense {
        let instructions = Instructions("""
You are an experienced expense categorizer. You are given a string of text that was recognized from
a receipt. You are to determine the following information from the receipt:
1. The total price of the item purchased (MOST IMPORTANT)
2. The name of what was purchased. For example, if you see a grocery receipt, you would note "Groceries". If you see a receipt for a TV, you would say "TV". The name of the store would suffice as well if you cannot determine the exact item or if there are multiple items.
3. The category of what this item/purchase would generally be. There are only two options: Needs or Wants. Needs describe expenses that are needed/must be spent. This includes rent, groceries, utility bills, and other payments. Wants are not needed and are leisure spends, such as new devices, eating out, shopping, and clothes. Pick the best option for the receipt.
4. The date the transaction occurred on. If no date is found, do NOT provide a date.
5. A tag that further describes the expense. You MUST pick EXACTLY ONE tag ONLY from the provided list. If no tag matches, do not provide a tag.

If the text in the image does not describe an receipt, then set the isReceipt flag to false and fill in dummy values for everything else.
""")
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Receipt Text: \(receiptText). Available Tags: \(tags.compactMap { $0.name }.joined(separator: ","))"

        do {
            let response = try await session.respond(to: prompt, generating: ParsedExpense.self)
            
            guard response.content.isReceipt else {
                throw ReceiptParserError.noReceipt
            }
            
            return response.content
        } catch {
            throw ReceiptParserError.parsingFailed
        }
    }
}

@available(iOS 26.0, *)
enum ReceiptParserError: LocalizedError {
    case languageModelUnavailable
    case imageEncodingFailed
    case textRecognitionFailed
    case noTextFound
    case noReceipt
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .languageModelUnavailable:
            "Receipt reading requires Apple Intelligence on this device."
        case .imageEncodingFailed:
            "Syl couldn't prepare this photo. Choose another photo and try again."
        case .textRecognitionFailed:
            "Syl couldn't read text from this photo. Try a clearer photo of the full receipt."
        case .noTextFound:
            "Syl couldn't find receipt text in this photo. Try a clearer photo of the full receipt."
        case .parsingFailed:
            "Syl couldn't read this photo. Please try again."
        case .noReceipt:
            "Please provide an image of a receipt, or try a different photo."
        }
    }
}

@available(iOS 26.0, *)
@Generable(description: "A collection of details for an expense parsed from a receipt")
struct ParsedExpense {
    @Guide(description: "A flag that denotes whether the supplied image/text is a receipt. If the image is not a receipt, set to false.")
    let isReceipt: Bool
    @Guide(description: "A short description of the expense, or where the expense came from. You should try to be as descriptive as possible in as little words as possible. For example, if the receipt seems to be a grocery receipt and is from the store 'Safeway', you would respond with 'Safeway'.")
    let name: String
    @Guide(description: "The total price of goods stated on the receipt. You may seem an itemized receipt with individual charges, and then a total charge. In general, the price you will note down is the highest price you see from the receipt text.")
    let price: Double
    @Guide(description: "The date the the transaction occured on, in YYYY-MM-DD format. YOU MUST RESPOND IN THIS FORMAT. If no date can be found, do not return a date.")
    let date: String?
    @Guide(description: "The catagory that this expense, in general, would fall into. Must be exactly ONE of the following: Needs, Wants. Needs are considered goods/services that are needed by a person, such as food (groceries, not dining out), rent/mortgage, etc. Wants are things that are not necessary, such as shopping, dining out, etc.")
    let category: String
    @Guide(description: "Users can add optional tags that further describe what bucket an expense falls into. Must be provided exactly as what is described in the list. If no tag matches closely enough, or no tags are provided, do not provide a tag.")
    let tag: String?
}
