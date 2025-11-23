// AudioRecordingManager.swift
// Handles saving audio recordings to disk

import AVFoundation
import Foundation
import Combine

/// Manages audio file recording and saving
class AudioRecordingManager: ObservableObject {
    static let shared = AudioRecordingManager()
    
    private var micAudioFile: AVAudioFile?
    private var systemAudioFile: AVAudioFile?
    private var micFileURL: URL?
    private var systemFileURL: URL?
    private var micFormat: AVAudioFormat?
    private var systemFormat: AVAudioFormat?
    
    // Track segments for each meeting to combine them later
    private var meetingSegments: [UUID: [URL]] = [:]
    
    private let documentsDirectory: URL
    private let recordingsDirectory: URL
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        recordingsDirectory = documentsDirectory.appendingPathComponent("Recordings")
        
        // Ensure recordings directory exists
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }
    
    /// Gets the folder URL for a specific meeting's audio files
    /// - Parameter meetingId: The ID of the meeting
    /// - Returns: The URL of the meeting's audio folder
    private func getMeetingFolder(for meetingId: UUID) -> URL {
        return recordingsDirectory.appendingPathComponent(meetingId.uuidString)
    }
    
    /// Starts recording audio for a meeting
    /// - Parameter meetingId: The ID of the meeting
    @MainActor
    func startRecording(for meetingId: UUID) {
        print("🎙️ Starting audio recording for meeting: \(meetingId)")
        
        // Create meeting-specific folder
        let meetingFolder = getMeetingFolder(for: meetingId)
        try? FileManager.default.createDirectory(at: meetingFolder, withIntermediateDirectories: true)
        
        // Create unique segment file URLs with timestamp to avoid overwriting
        let timestamp = Int(Date().timeIntervalSince1970)
        micFileURL = meetingFolder.appendingPathComponent("mic_\(timestamp).caf")
        systemFileURL = meetingFolder.appendingPathComponent("system_\(timestamp).caf")
        
        // Initialize segments array for this meeting if needed
        if meetingSegments[meetingId] == nil {
            meetingSegments[meetingId] = []
        }
    }
    
    /// Records a microphone audio buffer
    /// - Parameters:
    ///   - buffer: The audio buffer to record
    ///   - format: The audio format
    func recordMicBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Initialize mic file if needed
        if micAudioFile == nil, let fileURL = micFileURL {
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ]
                
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                micAudioFile = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
                micFormat = format
                print("✅ Created mic audio file: \(fileURL.lastPathComponent)")
            } catch {
                print("❌ Failed to create mic audio file: \(error)")
            }
        }
        
        // Write buffer to file
        if let file = micAudioFile {
            do {
                try file.write(from: buffer)
            } catch {
                print("❌ Failed to write mic audio buffer: \(error)")
            }
        }
    }
    
    /// Records a system audio buffer
    /// - Parameters:
    ///   - buffer: The audio buffer to record
    ///   - format: The audio format
    func recordSystemBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Initialize system file if needed
        if systemAudioFile == nil, let fileURL = systemFileURL {
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ]
                
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                systemAudioFile = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
                systemFormat = format
                print("✅ Created system audio file: \(fileURL.lastPathComponent)")
            } catch {
                print("❌ Failed to create system audio file: \(error)")
            }
        }
        
        // Write buffer to file
        if let file = systemAudioFile {
            do {
                try file.write(from: buffer)
            } catch {
                print("❌ Failed to write system audio buffer: \(error)")
            }
        }
    }
    
    /// Stops recording and saves the audio file
    /// - Parameter meetingId: The ID of the meeting
    /// - Returns: The URL of the saved audio file, or nil if failed
    @MainActor
    func stopRecordingAndSave(for meetingId: UUID) -> URL? {
        print("🛑 Stopping audio recording for meeting: \(meetingId)")
        
        // Close audio files
        micAudioFile = nil
        systemAudioFile = nil
        
        // Add current segment to the list if it exists
        var currentSegmentURL: URL? = nil
        if let micURL = micFileURL, FileManager.default.fileExists(atPath: micURL.path) {
            currentSegmentURL = micURL
            meetingSegments[meetingId, default: []].append(micURL)
            print("✅ Added mic segment: \(micURL.lastPathComponent)")
        } else if let systemURL = systemFileURL, FileManager.default.fileExists(atPath: systemURL.path) {
            currentSegmentURL = systemURL
            meetingSegments[meetingId, default: []].append(systemURL)
            print("✅ Added system segment: \(systemURL.lastPathComponent)")
        }
        
        // Create output file URL in meeting-specific folder
        let meetingFolder = getMeetingFolder(for: meetingId)
        try? FileManager.default.createDirectory(at: meetingFolder, withIntermediateDirectories: true)
        let outputURL = meetingFolder.appendingPathComponent("recording.m4a")
        
        // Get all segments for this meeting
        var allSegments = meetingSegments[meetingId] ?? []
        
        // Check if there's an existing final file - if so, we need to include it in the combination
        var existingFinalFile: URL? = nil
        if FileManager.default.fileExists(atPath: outputURL.path) {
            // Convert existing M4A to CAF format temporarily so we can combine it
            let tempCAF = meetingFolder.appendingPathComponent("existing_temp.caf")
            if convertM4AToCAF(sourceURL: outputURL, outputURL: tempCAF) != nil {
                existingFinalFile = tempCAF
                allSegments.insert(tempCAF, at: 0) // Add existing file at the beginning
                print("✅ Found existing audio file, will combine with new segments")
            }
        }
        
        guard !allSegments.isEmpty else {
            print("⚠️ No audio segments were recorded")
            return nil
        }
        
        print("🔗 Combining \(allSegments.count) segment(s) for meeting: \(meetingId)")
        
        // Combine all segments into one file
        if let combinedURL = combineSegments(segments: allSegments, outputURL: outputURL) {
            // Clean up segment files after combining
            for segmentURL in allSegments {
                try? FileManager.default.removeItem(at: segmentURL)
            }
            meetingSegments[meetingId] = nil // Clear segments for this meeting
            print("✅ Combined audio file saved: \(combinedURL.path)")
            return combinedURL
        }
        
        print("⚠️ Failed to combine audio segments")
        return nil
    }
    
    
    private func combineSegments(segments: [URL], outputURL: URL) -> URL? {
        guard !segments.isEmpty else { return nil }
        
        // If only one segment, just convert it
        if segments.count == 1 {
            return convertToM4A(sourceURL: segments[0], outputURL: outputURL)
        }
        
        // Combine multiple segments
        do {
            // Read first segment to get format
            let firstFile = try AVAudioFile(forReading: segments[0])
            let format = firstFile.processingFormat
            
            // Create output file
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 128000
            ])
            
            let bufferSize: AVAudioFrameCount = 4096
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
            
            // Append each segment to the output file
            for segmentURL in segments {
                let segmentFile = try AVAudioFile(forReading: segmentURL)
                segmentFile.framePosition = 0
                
                while segmentFile.framePosition < segmentFile.length {
                    try segmentFile.read(into: buffer)
                    try outputFile.write(from: buffer)
                }
                
                print("✅ Appended segment: \(segmentURL.lastPathComponent)")
            }
            
            return outputURL
        } catch {
            print("❌ Failed to combine segments: \(error)")
            return nil
        }
    }
    
    private func convertM4AToCAF(sourceURL: URL, outputURL: URL) -> URL? {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ], commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
            
            let bufferSize: AVAudioFrameCount = 4096
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
            
            sourceFile.framePosition = 0
            while sourceFile.framePosition < sourceFile.length {
                try sourceFile.read(into: buffer)
                try outputFile.write(from: buffer)
            }
            
            return outputURL
        } catch {
            print("❌ Failed to convert M4A to CAF: \(error)")
            return nil
        }
    }
    
    private func convertToM4A(sourceURL: URL, outputURL: URL) -> URL? {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 128000
            ])
            
            let bufferSize: AVAudioFrameCount = 4096
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
            
            sourceFile.framePosition = 0
            while sourceFile.framePosition < sourceFile.length {
                try sourceFile.read(into: buffer)
                try outputFile.write(from: buffer)
            }
            
            return outputURL
        } catch {
            print("❌ Failed to convert audio file: \(error)")
            return nil
        }
    }
    
    /// Deletes all audio files associated with a meeting
    /// - Parameter meetingId: The ID of the meeting
    func deleteAudioFiles(for meetingId: UUID) {
        let meetingFolder = getMeetingFolder(for: meetingId)
        
        // Delete the entire meeting folder (which contains all audio files)
        if FileManager.default.fileExists(atPath: meetingFolder.path) {
            do {
                try FileManager.default.removeItem(at: meetingFolder)
                print("✅ Deleted meeting audio folder: \(meetingFolder.lastPathComponent)")
            } catch {
                print("❌ Failed to delete meeting audio folder: \(error)")
            }
        }
        
        // Clear any tracked segments for this meeting
        meetingSegments[meetingId] = nil
    }
}

