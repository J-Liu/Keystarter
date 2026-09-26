// SensorReader.h
// Apple Silicon sensor reading via HID and IOReport

#import <Foundation/Foundation.h>

// Temperature sensor types
typedef NS_ENUM(NSInteger, SensorType) {
    SensorTypeTemperature = 0x0005,  // HID usage for temperature
    SensorTypeVoltage = 0x0003,
    SensorTypeCurrent = 0x0002,
};

// Power sensor groups
@interface PowerReadings : NSObject
@property (nonatomic) double CPU;
@property (nonatomic) double GPU;
@property (nonatomic) double ANE;  // Neural Engine
@property (nonatomic) double DRAM; // Memory
@property (nonatomic) double PCI;
@end

// Main sensor reader interface
@interface SensorReader : NSObject

// Read all temperature sensors
+ (NSDictionary<NSString *, NSNumber *> *)readTemperatures;

// Read specific sensor type
+ (NSDictionary<NSString *, NSNumber *> *)readSensorsWithType:(SensorType)type;

// Initialize power monitoring (call once)
- (void)setupPowerMonitoring;

// Read power values in Watts
- (PowerReadings *)readPower;

@end