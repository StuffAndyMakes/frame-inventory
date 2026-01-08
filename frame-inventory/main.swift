//
//  main.swift
//  frame-inventory
//
//  Created by Andy Frey on 1/5/26.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Data Model

struct ImageRecord: Codable {
    // Create ML requires the key 'image' for the file path
    let image: String
    // Create ML requires the key 'annotations' for the list of tags (for Multi-Label Classification)
    let annotations: [String]
}

enum FileOperation {
    case copy(destination: URL)
    case move(destination: URL)
}

// MARK: - Configuration

struct Configuration {
    let directoryURL: URL
    let outputURL: URL
    // Limit the number of examples per class to prevent imbalance
    let maxSamplesPerClass: Int?
    // Only print the stats, do not write the JSON file
    let summaryOnly: Bool
    // Whether to pick samples randomly or sequentially when balancing
    let randomizeSelection: Bool
    // File operation to perform on included images
    let fileOperation: FileOperation?
    // Verbose output
    let verbose: Bool
    // Dry run mode (simulate operations)
    let dryRun: Bool
}

// MARK: - Helper Functions

func printUsage() {
    print("""
    USAGE: frame-inventory [options]
    
    Generates a Create ML JSON manifest from Finder tags on images.
    
    OPTIONS:
      -d <path>         Directory to scan for images (default: current directory).
      -o <filename>     Output JSON filename (default: frames.json).
      -m, --max <int>   Max samples per class.
      -r, --random      Randomize selection when using -m (default: sequential/alphabetical).
      -s, --summary     Print inventory stats only (does not write JSON).
      --copy <path>     Copy the selected images to a destination directory.
      --move <path>     Move the selected images to a destination directory.
      -v, --verbose     Output details about every step and file.
      --dry-run         Simulate execution without modifying files or writing JSON.
      -h, --help        Show this help message.
    
    EXAMPLES:
      frame-inventory -d ./all_images -m 500 --copy ./training_set
      frame-inventory -s
      frame-inventory -d ./images -m 100 --dry-run -v
    """)
}

func parseArguments() -> Configuration {
    let args = CommandLine.arguments
    let fileManager = FileManager.default
    
    // Check for help immediately
    if args.contains("-h") || args.contains("--help") {
        printUsage()
        exit(0)
    }
    
    // Default values
    var directoryPath = fileManager.currentDirectoryPath
    var outputFilename = "frames.json"
    var maxSamples: Int? = nil
    var summaryOnly = false
    var randomizeSelection = false
    var fileOp: FileOperation? = nil
    var verbose = false
    var dryRun = false
    
    // Simple argument parsing
    for i in 0..<args.count {
        let arg = args[i]
        
        if arg == "-d" && i + 1 < args.count {
            directoryPath = args[i + 1]
        } else if arg == "-o" && i + 1 < args.count {
            outputFilename = args[i + 1]
        } else if (arg == "-m" || arg == "--max") && i + 1 < args.count {
            if let val = Int(args[i + 1]) {
                maxSamples = val
            }
        } else if arg == "-s" || arg == "--summary" {
            summaryOnly = true
        } else if arg == "-r" || arg == "--random" {
            randomizeSelection = true
        } else if arg == "--copy" && i + 1 < args.count {
            let destPath = args[i + 1]
            let destURL = URL(fileURLWithPath: destPath).standardized
            fileOp = .copy(destination: destURL)
        } else if arg == "--move" && i + 1 < args.count {
            let destPath = args[i + 1]
            let destURL = URL(fileURLWithPath: destPath).standardized
            fileOp = .move(destination: destURL)
        } else if arg == "-v" || arg == "--verbose" {
            verbose = true
        } else if arg == "--dry-run" {
            dryRun = true
        }
    }
    
    // Resolve paths
    let directoryURL = URL(fileURLWithPath: directoryPath).standardized
    let outputURL = URL(fileURLWithPath: outputFilename, relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath)).standardized
    
    return Configuration(
        directoryURL: directoryURL,
        outputURL: outputURL,
        maxSamplesPerClass: maxSamples,
        summaryOnly: summaryOnly,
        randomizeSelection: randomizeSelection,
        fileOperation: fileOp,
        verbose: verbose,
        dryRun: dryRun
    )
}

func scanForImages(config: Configuration) throws -> [ImageRecord] {
    let fileManager = FileManager.default
    var records: [ImageRecord] = []
    
    // We need the tag names key to see Finder tags
    let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey, .tagNamesKey]
    
    if config.verbose {
        print("Scanning \(config.directoryURL.path)...")
    }
    
    let enumerator = fileManager.enumerator(
        at: config.directoryURL,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    
    guard let fileEnumerator = enumerator else {
        return []
    }
    
    for case let fileURL as URL in fileEnumerator {
        // Retrieve resource values
        let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
        
        // Ensure it's a regular file and an image
        guard let isRegularFile = resourceValues?.isRegularFile, isRegularFile,
              let contentType = resourceValues?.contentType, contentType.conforms(to: .image)
        else {
            continue
        }
        
        // Extract Finder Tags
        let tags = resourceValues?.tagNames ?? []
        
        // Normalize tags.
        var uniqueLabels = Set<String>()
        
        for tag in tags {
            let lower = tag.lowercased()
            if lower.contains("woodpecker") {
                uniqueLabels.insert("woodpecker")
            } else if lower.contains("hummingbird") {
                uniqueLabels.insert("hummingbird")
            } else if lower.contains("other") {
                uniqueLabels.insert("other")
            }
        }
        
        // Use relative filename since all images are in one directory.
        let record = ImageRecord(image: fileURL.lastPathComponent, annotations: Array(uniqueLabels).sorted())
        records.append(record)
        
        if config.verbose {
            print("   Found: \(record.image) -> Tags: \(record.annotations)")
        }
    }
    
    return records
}

/// Downsamples the records to ensure no class exceeds the specified limit.
func balanceDataset(records: [ImageRecord], maxPerClass: Int, randomize: Bool, verbose: Bool) -> [ImageRecord] {
    print("\n⚖️ Balancing dataset to max \(maxPerClass) samples per class...")
    if randomize {
        print("   Strategy: Random selection")
    } else {
        print("   Strategy: Sequential selection (Alphabetical)")
    }
    
    var counts: [String: Int] = [:]
    var balancedRecords: [ImageRecord] = []
    
    // Determine processing order
    let sourceRecords: [ImageRecord]
    if randomize {
        sourceRecords = records.shuffled()
    } else {
        // Sort alphabetically to ensure deterministic "First N" behavior
        sourceRecords = records.sorted { $0.image < $1.image }
    }
    
    for record in sourceRecords {
        // Handle untagged / background images
        if record.annotations.isEmpty {
            let bgKey = "(Background)"
            if counts[bgKey, default: 0] < maxPerClass {
                balancedRecords.append(record)
                counts[bgKey, default: 0] += 1
                if verbose { print("   [KEEP] \(record.image) (Background)") }
            } else {
                if verbose { print("   [SKIP] \(record.image) (Background limit reached)") }
            }
            continue
        }
        
        // Check if adding this record would violate the limit for ANY of its tags
        var canAdd = true
        for tag in record.annotations {
            if counts[tag, default: 0] >= maxPerClass {
                canAdd = false
                if verbose { print("   [SKIP] \(record.image) (Limit reached for '\(tag)')") }
                break
            }
        }
        
        if canAdd {
            balancedRecords.append(record)
            for tag in record.annotations {
                counts[tag, default: 0] += 1
            }
            if verbose { print("   [KEEP] \(record.image) \(record.annotations)") }
        }
    }
    
    // Always return sorted output for clean JSON
    return balancedRecords.sorted { $0.image < $1.image }
}

func performFileOperations(records: [ImageRecord], config: Configuration) throws {
    guard let operation = config.fileOperation else { return }
    let fileManager = FileManager.default
    
    let destURL: URL
    let isMove: Bool
    let opName: String
    
    switch operation {
    case .copy(let url):
        destURL = url
        isMove = false
        opName = "Copy"
    case .move(let url):
        destURL = url
        isMove = true
        opName = "Move"
    }
    
    let dryRunPrefix = config.dryRun ? "[DRY RUN] " : ""
    print("\n\(dryRunPrefix)Performing \(opName) on \(records.count) files to: \(destURL.path)")

    if !config.dryRun {
        // Create destination directory if needed
        if !fileManager.fileExists(atPath: destURL.path) {
            try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true, attributes: nil)
        }
    } else {
        if config.verbose { print("\(dryRunPrefix)Would create directory: \(destURL.path)") }
    }
    
    for record in records {
        let sourceURL = config.directoryURL.appendingPathComponent(record.image)
        let destinationFile = destURL.appendingPathComponent(record.image)
        
        if config.dryRun {
             if config.verbose {
                 print("\(dryRunPrefix)Would \(opName.lowercased()) \(record.image)")
             }
        } else {
            if fileManager.fileExists(atPath: destinationFile.path) {
                // Skip if exists to prevent crash
                if config.verbose { print("   Skipping \(record.image) (exists at dest)") }
                continue
            }
            
            if config.verbose { print("   \(opName)ing \(record.image)...") }
            
            if isMove {
                try fileManager.moveItem(at: sourceURL, to: destinationFile)
            } else {
                try fileManager.copyItem(at: sourceURL, to: destinationFile)
            }
        }
    }
    
    if config.dryRun {
        print("\(dryRunPrefix)Operation simulation complete.")
    } else {
        print("✅ File operation complete.")
    }
}

// MARK: - Main Execution

do {
    let config = parseArguments()
    
    if config.dryRun {
        print("⚠️ DRY RUN MODE ENABLED: No changes will be made to the filesystem.\n")
    }
    
    print("Scanning directory: \(config.directoryURL.path)")
    if config.summaryOnly {
        print("(Summary Mode: No JSON will be written)")
    }
    
    var records = try scanForImages(config: config)
    
    // Apply Balancing if requested
    if let limit = config.maxSamplesPerClass {
        records = balanceDataset(records: records, maxPerClass: limit, randomize: config.randomizeSelection, verbose: config.verbose)
    }
    
    // --- Detailed Statistics ---
    var labelCounts: [String: Int] = [:]
    var combinationCounts: [String: Int] = [:]
    
    for record in records {
        if record.annotations.isEmpty {
            labelCounts["(No Tag / Background)", default: 0] += 1
            combinationCounts["(No Tag / Background)", default: 0] += 1
        } else {
            // Count individual labels
            for label in record.annotations {
                labelCounts[label, default: 0] += 1
            }
            
            // Count specific combinations (e.g., "hummingbird AND woodpecker")
            let comboKey = "[" + record.annotations.sorted().joined(separator: ", ") + "]"
            combinationCounts[comboKey, default: 0] += 1
        }
    }
    
    print("\n--- Inventory Summary ---")
    print("Total Files: \(records.count)")
    
    print("\nLabel Counts (Cumulative):")
    let sortedCounts = labelCounts.sorted { $0.key < $1.key }
    for (label, count) in sortedCounts {
        print("• \(label): \(count)")
    }
    
    print("\nExact Combination Counts:")
    let sortedCombinations = combinationCounts.sorted { $0.key < $1.key }
    for (combo, count) in sortedCombinations {
        print("• \(combo): \(count)")
    }
    print("-------------------------\n")
    
    // If Summary Only mode, exit here
    if config.summaryOnly {
        exit(0)
    }
    
    // Perform Copy/Move if requested
    try performFileOperations(records: records, config: config)
    
    // --------------------------------
    
    if config.dryRun {
        print("[DRY RUN] Would write JSON manifest to: \(config.outputURL.path)")
        print("[DRY RUN] content would contain \(records.count) records.")
    } else {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(records)
        
        try jsonData.write(to: config.outputURL)
        print("Inventory saved to: \(config.outputURL.path)")
    }
    
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}

