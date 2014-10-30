//
//  main.swift
//  sourcekitten
//
//  Created by JP Simard on 10/15/14.
//  Copyright (c) 2014 Realm. All rights reserved.
//

import Foundation
import XPC

// MARK: Structure

/**
Print file structure information as JSON to STDOUT

:param: file Path to the file to parse for structure information
*/
func printStructure(#file: String) {
    // Construct a SourceKit request for getting general info about a Swift file
    let request = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_uint64(request, "key.request", sourcekitd_uid_get_from_cstr("source.request.editor.open"))
    xpc_dictionary_set_string(request, "key.name", "")
    xpc_dictionary_set_string(request, "key.sourcefile", file)

    // Initialize SourceKit XPC service
    sourcekitd_initialize()

    // Send SourceKit request
    var response: XPCDictionary = fromXPC(sourcekitd_send_request_sync(request))
    response.removeValueForKey("key.syntaxmap")
    var declarationOffsets = [Int64, String]()
    replaceUIDsWithStringsInDictionary(response, declarationOffsets: &declarationOffsets)
    println(toJSON(response))
}

// MARK: Syntax

/**
Print syntax highlighting information as JSON to STDOUT

:param: file Path to the file to parse for syntax highlighting information
*/
func printSyntaxHighlighting(#file: String) {
    // Construct a SourceKit request for getting general info about the Swift file passed as argument
    let request = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_uint64(request, "key.request", sourcekitd_uid_get_from_cstr("source.request.editor.open"))
    xpc_dictionary_set_string(request, "key.name", "")
    xpc_dictionary_set_string(request, "key.sourcefile", file)

    // Initialize SourceKit XPC service
    sourcekitd_initialize()

    // Send SourceKit request
    let response = sourcekitd_send_request_sync(request)
    printSyntaxHighlighting(response)
}

/**
Print syntax highlighting information as JSON to STDOUT

:param: text Swift source code to parse for syntax highlighting information
*/
func printSyntaxHighlighting(#text: String) {
    // Construct a SourceKit request for getting general info about the Swift source text passed as argument
    let request = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_uint64(request, "key.request", sourcekitd_uid_get_from_cstr("source.request.editor.open"))
    xpc_dictionary_set_string(request, "key.name", "")
    xpc_dictionary_set_string(request, "key.sourcetext", text)

    // Initialize SourceKit XPC service
    sourcekitd_initialize()

    // Send SourceKit request
    let response = sourcekitd_send_request_sync(request)
    printSyntaxHighlighting(response)
}

/**
Print syntax highlighting information as JSON to STDOUT

:param: sourceKitResponse XPC object returned from SourceKit "editor.open" call
*/
func printSyntaxHighlighting(sourceKitResponse: xpc_object_t) {
    // Get syntaxmap XPC data and convert to NSData
    let data: NSData = fromXPC(xpc_dictionary_get_value(sourceKitResponse, "key.syntaxmap"))!

    // Get number of syntax tokens
    var tokens = 0
    data.getBytes(&tokens, range: NSRange(location: 8, length: 8))
    tokens = tokens >> 4

    println("[")

    for i in 0..<tokens {
        let parserOffset = 16 * i

        var uid = UInt64(0)
        data.getBytes(&uid, range: NSRange(location: 16 + parserOffset, length: 8))
        let type = String(UTF8String: sourcekitd_uid_get_string_ptr(uid))!

        var offset = 0
        data.getBytes(&offset, range: NSRange(location: 24 + parserOffset, length: 4))

        var length = 0
        data.getBytes(&length, range: NSRange(location: 28 + parserOffset, length: 4))
        length = length >> 1

        print("  {\n    \"type\": \"\(type)\",\n    \"offset\": \(offset),\n    \"length\": \(length)\n  }")

        if i != tokens-1 {
            println(",")
        } else {
            println()
        }
    }

    println("]")
}

// MARK: Helper Functions

/**
Print error message to STDERR

:param: error message to print
*/
func error(message: String) {
    let stderr = NSFileHandle.fileHandleWithStandardError()
    stderr.writeData(message.dataUsingEncoding(NSUTF8StringEncoding)!)
    exit(1)
}

/**
Replace all UIDs in a SourceKit response dictionary with their string values.

:param:   dictionary         `XPCDictionary` to mutate.
:param:   declarationOffsets inout `Array` of (`Int64`, `String`) tuples. First value is offset of declaration.
                             Second value is declaration kind (i.e. `source.lang.swift.decl.function.free`).
*/
func replaceUIDsWithStringsInDictionary(var dictionary: XPCDictionary, inout #declarationOffsets: [(Int64, String)]) {
    for key in dictionary.keys {
        if let subArray = dictionary[key]! as? XPCArray {
            for subDict in subArray {
                replaceUIDsWithStringsInDictionary(subDict as XPCDictionary,
                    declarationOffsets: &declarationOffsets)
            }
        } else if let uid = dictionary[key] as? UInt64 {
            if uid > 4_300_000_000 { // UID's are all higher than 4.3M
                if let utf8String = sourcekitd_uid_get_string_ptr(uid) as UnsafePointer<Int8>? {
                    let uidString = String(UTF8String: utf8String)!
                    dictionary[key] = uidString
                    if key == "key.kind" &&
                        uidString.rangeOfString("source.lang.swift.decl.") != nil {
                        let offset = dictionary["key.nameoffset"] as Int64
                        if offset > 0 {
                            declarationOffsets.append(offset, uidString)
                        }
                    }
                }
            }
        }
    }
}

/**
Convert XPCDictionary to JSON

:param: dictionary XPCDictionary to convert
:returns: Converted JSON
*/
func toJSON(dictionary: XPCDictionary) -> String {
    let json = toJSONPartial(dictionary)
        .stringByReplacingOccurrencesOfString(",}", withString: "}")
        .stringByReplacingOccurrencesOfString(",]", withString: "]")

    let jsonData = json[json.startIndex..<json.endIndex.predecessor()].dataUsingEncoding(NSUTF8StringEncoding)!
    let prettyJSONObject: AnyObject? = NSJSONSerialization.JSONObjectWithData(jsonData, options: nil, error: nil)
    let prettyJSONData = NSJSONSerialization.dataWithJSONObject(prettyJSONObject!, options: .PrettyPrinted, error: nil)
    return NSString(data: prettyJSONData!, encoding: NSUTF8StringEncoding)!
}

/**
Partially convert XPCDictionary to JSON. Is not yet valid JSON. See toJSON(_:)

:param: dictionary XPCDictionary to convert
:returns: Converted JSON
*/
func toJSONPartial(dictionary: XPCDictionary) -> String {
    var json = "{"
    for (key, object) in dictionary {
        switch object {
        case let object as XPCArray:
            json += "\"\(key)\": ["
            for subDict in object {
                json += toJSONPartial(subDict as XPCDictionary)
            }
            json += "],"
        case let object as XPCDictionary:
            json += "\"\(key)\": \(toJSONPartial(object)),"
        case let object as String:
            let escapedString = object.stringByAddingPercentEscapesUsingEncoding(NSUTF8StringEncoding)!
            json += "\"\(key)\": \"\(escapedString)\","
        case let object as NSDate:
            json += "\"\(key)\": \"\(object)\","
        case let object as NSData:
            json += "\"\(key)\": \"\(object)\","
        case let object as UInt64:
            if object > 4_300_000_000 { // UID's are all higher than 4.3M
                if let utf8String = sourcekitd_uid_get_string_ptr(object) as UnsafePointer<Int8>? {
                    let uidString = String(UTF8String: utf8String)!
                    json += "\"\(key)\": \"\(uidString)\","
                }
            } else {
                json += "\"\(key)\": \(object),"
            }
        case let object as Int64:
            json += "\"\(key)\": \(object),"
        case let object as Double:
            json += "\"\(key)\": \(object),"
        case let object as Bool:
            json += "\"\(key)\": \(object),"
        case let object as NSFileHandle:
            json += "\"\(key)\": \(object.fileDescriptor),"
        default:
            // Should never happen because we've checked all XPCRepresentable types
            abort()
        }
    }
    json += "},"
    return json
}

/**
Run `xcodebuild clean build -dry-run` along with any passed in build arguments.
Return STDERR and STDOUT as a combined string.

:param: processArguments array of arguments to pass to `xcodebuild`
:returns: xcodebuild STDERR+STDOUT output
*/
func run_xcodebuild(processArguments: [String]) -> String? {
    let task = NSTask()
    task.currentDirectoryPath = "/Users/jp/Projects/sourcekitten"
    task.launchPath = "/usr/bin/xcodebuild"

    // Forward arguments to xcodebuild
    var arguments = processArguments
    arguments.removeAtIndex(0)
    arguments.extend(["clean", "build", "-dry-run"])
    task.arguments = arguments

    let pipe = NSPipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.launch()

    let file = pipe.fileHandleForReading
    let xcodebuildOutput = NSString(data: file.readDataToEndOfFile(), encoding: NSUTF8StringEncoding)
    file.closeFile()

    return xcodebuildOutput
}

/**
Parses the compiler arguments needed to compile the Swift aspects of an Xcode project

:param: xcodebuildOutput output of `xcodebuild` to be parsed for swift compiler arguments
:returns: array of swift compiler arguments
*/
func swiftc_arguments_from_xcodebuild_output(xcodebuildOutput: NSString) -> [String]? {
    let regex = NSRegularExpression(pattern: "/usr/bin/swiftc.*", options: NSRegularExpressionOptions(0), error: nil)!
    let range = NSRange(location: 0, length: xcodebuildOutput.length)
    let regexMatch = regex.firstMatchInString(xcodebuildOutput, options: NSMatchingOptions(0), range: range)

    if let regexMatch = regexMatch {
        let escapedSpacePlaceholder = "\u{0}"
        var args = xcodebuildOutput
            .substringWithRange(regexMatch.range)
            .stringByReplacingOccurrencesOfString("\\ ", withString: escapedSpacePlaceholder)
            .componentsSeparatedByString(" ")

        args.removeAtIndex(0) // Remove swiftc

        args.map {
            $0.stringByReplacingOccurrencesOfString(escapedSpacePlaceholder, withString: " ")
        }

        return args.filter { $0 != "-parseable-output" }
    }

    return nil
}

/**
Print XML-formatted docs for the specified Xcode project

:param: arguments compiler arguments to pass to SourceKit
:param: swiftFiles array of Swift file names to document
:returns: XML-formatted string of documentation for the specified Xcode project
*/
func docs_for_swift_compiler_args(arguments: [String], swiftFiles: [String]) -> String {
    sourcekitd_initialize()

    // Create the XPC array of compiler arguments once, to be reused for each request
    let xpcArguments = xpc_array_create(nil, 0)
    for argument in arguments {
        xpc_array_append_value(xpcArguments, xpc_string_create(argument))
    }

    // Construct a SourceKit request for getting general info about a Swift file
    let openRequest = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_uint64(openRequest, "key.request", sourcekitd_uid_get_from_cstr("source.request.editor.open"))
    xpc_dictionary_set_string(openRequest, "key.name", "")

    var xmlDocs = [String]()

    // Print docs for each Swift file
    for file in swiftFiles {
        xpc_dictionary_set_string(openRequest, "key.sourcefile", file)

        var declarationOffsets = [Int64, String]()

        let openResponse: XPCDictionary = fromXPC(sourcekitd_send_request_sync(openRequest))
        replaceUIDsWithStringsInDictionary(openResponse, declarationOffsets: &declarationOffsets)
        println(toJSON(openResponse))

        // Construct a SourceKit request for getting cursor info for current cursor position
        let cursorInfoRequest = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(cursorInfoRequest, "key.request", sourcekitd_uid_get_from_cstr("source.request.cursorinfo"))
        xpc_dictionary_set_value(cursorInfoRequest, "key.compilerargs", xpcArguments)
        xpc_dictionary_set_string(cursorInfoRequest, "key.sourcefile", file)

        // Send "cursorinfo" SourceKit request for each cursor position in the current file.
        //
        // This is the same request triggered by Option-clicking a token in Xcode,
        // so we are also generating documentation for code that is external to the current project,
        // which is why we filter out docs from outside this file.
        for cursor in declarationOffsets {
            xpc_dictionary_set_int64(cursorInfoRequest, "key.offset", cursor.0)

            // Send request and wait for response
            if let response = fromXPC(sourcekitd_send_request_sync(cursorInfoRequest)) as XPCDictionary? {
                if contains(response.keys, "key.doc.full_as_xml") {
                    let xml = response["key.doc.full_as_xml"]! as String
                    xmlDocs.append(xml.stringByReplacingOccurrencesOfString("</Name><USR>", withString: "</Name><Kind>\(cursor.1)</Kind><USR>"))
                } else if let usr = response["key.usr"] {
                    let name = response["key.name"]!
                    let decl = response["key.annotated_decl"]!
                    xmlDocs.append("<Other file=\"\(file)\"><Name>\(name)</Name><Kind>\(cursor.1)</Kind><USR>\(usr)</USR>\(decl)</Other>")
                }
            }
        }
    }

    var docsString = "<jazzy>\n"
    for xml in xmlDocs {
        docsString += "\(xml)\n"
    }
    docsString += "</jazzy>"
    return docsString
}

/**
Returns an array of swift file names in an array

:param: array Array to be filtered
:returns: the array of swift files
*/
func swiftFilesFromArray(array: [String]) -> [String] {
    return array.filter {
        $0.rangeOfString(".swift", options: (.BackwardsSearch | .AnchoredSearch)) != nil
    }
}

// MARK: Main Program

/**
Print XML-formatted docs for the specified Xcode project,
or Xcode output if no Swift compiler arguments were found.
*/
func main() {
    let arguments = Process.arguments
    if arguments.count > 1 && arguments[1] == "--skip-xcodebuild" {
        var sourcekitdArguments = arguments
        sourcekitdArguments.removeAtIndex(0) // remove sourcekitten
        sourcekitdArguments.removeAtIndex(0) // remove --skip-xcodebuild
        let swiftFiles = swiftFilesFromArray(sourcekitdArguments)
        println(docs_for_swift_compiler_args(sourcekitdArguments, swiftFiles))
    } else if arguments.count == 3 && arguments[1] == "--structure" {
        printStructure(file: arguments[2])
    } else if arguments.count == 3 && arguments[1] == "--syntax" {
        printSyntaxHighlighting(file: arguments[2])
    } else if arguments.count == 3 && arguments[1] == "--syntax-text" {
        printSyntaxHighlighting(text: arguments[2])
    } else if let xcodebuildOutput = run_xcodebuild(arguments) {
        if let swiftcArguments = swiftc_arguments_from_xcodebuild_output(xcodebuildOutput) {
            // Extract the Xcode project's Swift files
            let swiftFiles = swiftFilesFromArray(swiftcArguments)

            // FIXME: The following makes things ~30% faster, at the expense of (possibly)
            // not supporting complex project configurations.
            // Extract the minimum Swift compiler arguments needed for SourceKit
            var sourcekitdArguments = Array<String>(swiftcArguments[0..<7])
            sourcekitdArguments.extend(swiftFiles)
            
            println(docs_for_swift_compiler_args(sourcekitdArguments, swiftFiles))
        } else {
            error(xcodebuildOutput)
        }
    } else {
        error("Xcode build output could not be read")
    }
}

main()
