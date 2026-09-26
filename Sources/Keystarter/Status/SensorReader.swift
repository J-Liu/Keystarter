// SensorReader.swift
// Swift wrapper for Objective-C SensorReader

import Foundation
import SensorReader

// Swift-friendly wrapper
public final class SensorReaderSwift {
    private let reader = SensorReader()
    
    public static func readTemperatures() -> [String: Double] {
        guard let result = SensorReader.readTemperatures() else {
            return [:]
        }
        return result.mapValues { $0.doubleValue }
    }
    
    public func setupPowerMonitoring() {
        reader.setupPowerMonitoring()
    }
    
    public func readPower() -> PowerReadings {
        guard let readings = reader.readPower() else {
            return PowerReadings()
        }
        let result = PowerReadings()
        result.cpu = readings.cpu
        result.gpu = readings.gpu
        result.ane = readings.ane
        result.dram = readings.dram
        result.pci = readings.pci
        return result
    }
}