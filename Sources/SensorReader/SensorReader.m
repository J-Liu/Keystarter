// SensorReader.m
// Apple Silicon sensor reading via HID and IOReport
// Based on exelban/stats implementation

#import "SensorReader.h"
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

// Forward declare private types
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOReportSubscription *IOReportSubscriptionRef;

// Function pointer types
typedef IOHIDEventSystemClientRef (*IOHIDEventSystemClientCreateFunc)(CFAllocatorRef allocator);
typedef void (*IOHIDEventSystemClientSetMatchingFunc)(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
typedef CFArrayRef (*IOHIDEventSystemClientCopyServicesFunc)(IOHIDEventSystemClientRef client);
typedef CFTypeRef (*IOHIDServiceClientCopyPropertyFunc)(IOHIDServiceClientRef service, CFStringRef key);
typedef IOHIDEventRef (*IOHIDServiceClientCopyEventFunc)(IOHIDServiceClientRef service, int32_t eventType, uint64_t timestamp, uint64_t options);
typedef double (*IOHIDEventGetFloatValueFunc)(IOHIDEventRef event, int32_t field);
typedef int32_t (*IOHIDEventFieldBaseFunc)(int32_t eventType);

typedef IOReportSubscriptionRef (*IOReportCreateSubscriptionFunc)(CFAllocatorRef allocator, CFArrayRef channels, CFArrayRef *subscribed, uint64_t flags, int32_t *error);
typedef CFArrayRef (*IOReportCreateChannelsFunc)(CFAllocatorRef allocator, CFStringRef interest);
typedef int64_t (*IOReportSimpleGetIntegerValueFunc)(CFDictionaryRef channel, int sample_idx);
typedef CFStringRef (*IOReportChannelGetGroupFunc)(CFDictionaryRef channel);
typedef CFStringRef (*IOReportChannelGetChannelNameFunc)(CFDictionaryRef channel);
typedef CFStringRef (*IOReportChannelGetUnitLabelFunc)(CFDictionaryRef channel);
typedef CFDictionaryRef (*IOReportCreateSamplesFunc)(IOReportSubscriptionRef subscription, CFArrayRef channels, CFArrayRef previous);

// Static function pointers
static IOHIDEventSystemClientCreateFunc _IOHIDEventSystemClientCreate = NULL;
static IOHIDEventSystemClientSetMatchingFunc _IOHIDEventSystemClientSetMatching = NULL;
static IOHIDEventSystemClientCopyServicesFunc _IOHIDEventSystemClientCopyServices = NULL;
static IOHIDServiceClientCopyPropertyFunc _IOHIDServiceClientCopyProperty = NULL;
static IOHIDServiceClientCopyEventFunc _IOHIDServiceClientCopyEvent = NULL;
static IOHIDEventGetFloatValueFunc _IOHIDEventGetFloatValue = NULL;
static IOHIDEventFieldBaseFunc _IOHIDEventFieldBase = NULL;

static IOReportCreateSubscriptionFunc _IOReportCreateSubscription = NULL;
static IOReportCreateChannelsFunc _IOReportCreateChannels = NULL;
static IOReportSimpleGetIntegerValueFunc _IOReportSimpleGetIntegerValue = NULL;
static IOReportChannelGetGroupFunc _IOReportChannelGetGroup = NULL;
static IOReportChannelGetChannelNameFunc _IOReportChannelGetChannelName = NULL;
static IOReportChannelGetUnitLabelFunc _IOReportChannelGetUnitLabel = NULL;
static IOReportCreateSamplesFunc _IOReportCreateSamples = NULL;

static BOOL _functionsLoaded = NO;

// Load private functions using dlsym
static void loadPrivateFunctions(void) {
    if (_functionsLoaded) return;
    
    void *handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) return;
    
    // HID functions
    _IOHIDEventSystemClientCreate = (IOHIDEventSystemClientCreateFunc)dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventSystemClientSetMatching = (IOHIDEventSystemClientSetMatchingFunc)dlsym(handle, "IOHIDEventSystemClientSetMatching");
    _IOHIDEventSystemClientCopyServices = (IOHIDEventSystemClientCopyServicesFunc)dlsym(handle, "IOHIDEventSystemClientCopyServices");
    _IOHIDServiceClientCopyProperty = (IOHIDServiceClientCopyPropertyFunc)dlsym(handle, "IOHIDServiceClientCopyProperty");
    _IOHIDServiceClientCopyEvent = (IOHIDServiceClientCopyEventFunc)dlsym(handle, "IOHIDServiceClientCopyEvent");
    _IOHIDEventGetFloatValue = (IOHIDEventGetFloatValueFunc)dlsym(handle, "IOHIDEventGetFloatValue");
    _IOHIDEventFieldBase = (IOHIDEventFieldBaseFunc)dlsym(handle, "IOHIDEventFieldBase");
    
    // IOReport functions
    _IOReportCreateSubscription = (IOReportCreateSubscriptionFunc)dlsym(handle, "IOReportCreateSubscription");
    _IOReportCreateChannels = (IOReportCreateChannelsFunc)dlsym(handle, "IOReportCreateChannels");
    _IOReportSimpleGetIntegerValue = (IOReportSimpleGetIntegerValueFunc)dlsym(handle, "IOReportSimpleGetIntegerValue");
    _IOReportChannelGetGroup = (IOReportChannelGetGroupFunc)dlsym(handle, "IOReportChannelGetGroup");
    _IOReportChannelGetChannelName = (IOReportChannelGetChannelNameFunc)dlsym(handle, "IOReportChannelGetChannelName");
    _IOReportChannelGetUnitLabel = (IOReportChannelGetUnitLabelFunc)dlsym(handle, "IOReportChannelGetUnitLabel");
    _IOReportCreateSamples = (IOReportCreateSamplesFunc)dlsym(handle, "IOReportCreateSamples");
    
    dlclose(handle);
    _functionsLoaded = YES;
}

// Power readings implementation
@implementation PowerReadings
@end

@implementation SensorReader {
    IOReportSubscriptionRef _subscription;
    CFArrayRef _channels;
    NSDictionary *_prevPowers;
    NSDate *_lastRead;
}

#pragma mark - Temperature Reading

+ (NSDictionary<NSString *, NSNumber *> *)readTemperatures {
    return [self readSensorsWithType:SensorTypeTemperature];
}

+ (NSDictionary<NSString *, NSNumber *> *)readSensorsWithType:(SensorType)type {
    loadPrivateFunctions();
    
    if (!_IOHIDEventSystemClientCreate || !_IOHIDEventSystemClientSetMatching ||
        !_IOHIDEventSystemClientCopyServices || !_IOHIDServiceClientCopyProperty ||
        !_IOHIDServiceClientCopyEvent || !_IOHIDEventGetFloatValue) {
        return nil;
    }
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    // Create HID event system client
    IOHIDEventSystemClientRef system = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!system) {
        return nil;
    }
    
    // Set matching criteria
    // Page 0xFF00 (65280) is the Apple-specific HID page
    // Usage varies by sensor type
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(0xFF00),
        @"PrimaryUsage": @(type)
    };
    _IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);
    
    // Get services
    CFArrayRef services = _IOHIDEventSystemClientCopyServices(system);
    if (!services) {
        CFRelease(system);
        return nil;
    }
    
    // Iterate through services
    for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        
        // Get sensor name
        NSString *name = CFBridgingRelease(_IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        if (!name) {
            continue;
        }
        
        // Get event with value
        IOHIDEventRef event = _IOHIDServiceClientCopyEvent(service, (int32_t)type, 0, 0);
        if (!event) {
            continue;
        }
        
        // Extract value - field is the usage value directly
        // IOHIDEventFieldBase(eventType) = eventType, so we use type directly
        double value = _IOHIDEventGetFloatValue(event, (int32_t)type);
        result[name] = @(value);
        
        CFRelease(event);
    }
    
    CFRelease(services);
    CFRelease(system);
    
    return [result copy];
}

#pragma mark - Power Reading

- (instancetype)init {
    self = [super init];
    if (self) {
        _prevPowers = @{
            @"CPU": @0,
            @"GPU": @0,
            @"ANE": @0,
            @"DRAM": @0,
            @"PCI": @0
        };
    }
    return self;
}

- (void)setupPowerMonitoring {
    loadPrivateFunctions();
    
    if (!_IOReportCreateChannels || !_IOReportCreateSubscription) {
        return;
    }
    
    // Create IOReport subscription for energy monitoring
    CFStringRef interest = CFSTR("Energy Model");
    _channels = _IOReportCreateChannels(kCFAllocatorDefault, interest);
    
    if (_channels) {
        CFArrayRef subscribed = nil;
        _subscription = _IOReportCreateSubscription(kCFAllocatorDefault, _channels, &subscribed, 0, NULL);
        if (subscribed) CFRelease(subscribed);
    }
}

- (PowerReadings *)readPower {
    PowerReadings *readings = [[PowerReadings alloc] init];
    
    if (!_subscription || !_IOReportCreateSamples || !_IOReportChannelGetGroup ||
        !_IOReportChannelGetChannelName || !_IOReportChannelGetUnitLabel || !_IOReportSimpleGetIntegerValue) {
        return readings;
    }
    
    // Get current samples
    CFDictionaryRef sampleDict = _IOReportCreateSamples(_subscription, _channels, NULL);
    if (!sampleDict) {
        return readings;
    }
    
    NSDictionary *dict = CFBridgingRelease(sampleDict);
    NSArray *channels = dict[@"IOReportChannels"];
    if (!channels) {
        return readings;
    }
    
    NSDate *now = [NSDate date];
    NSMutableDictionary *currentPowers = [NSMutableDictionary dictionary];
    
    // Read energy values
    for (id item in channels) {
        CFDictionaryRef channel = (__bridge CFDictionaryRef)item;
        
        NSString *group = CFBridgingRelease(_IOReportChannelGetGroup(channel));
        if (!group || ![group isEqualToString:@"Energy Model"]) {
            continue;
        }
        
        NSString *channelName = CFBridgingRelease(_IOReportChannelGetChannelName(channel));
        NSString *unit = CFBridgingRelease(_IOReportChannelGetUnitLabel(channel));
        int64_t value = _IOReportSimpleGetIntegerValue(channel, 0);
        
        // Convert to Joules based on unit
        double energy = value;
        if ([unit isEqualToString:@"mJ"]) {
            energy = value / 1000.0;
        } else if ([unit isEqualToString:@"µJ"]) {
            energy = value / 1000000.0;
        }
        
        // Categorize by channel name
        if ([channelName hasSuffix:@"CPU Energy"]) {
            currentPowers[@"CPU"] = @(energy);
        } else if ([channelName hasSuffix:@"GPU Energy"]) {
            currentPowers[@"GPU"] = @(energy);
        } else if ([channelName hasPrefix:@"ANE"]) {
            currentPowers[@"ANE"] = @(energy);
        } else if ([channelName hasPrefix:@"DRAM"]) {
            currentPowers[@"DRAM"] = @(energy);
        } else if ([channelName hasPrefix:@"PCI"] && [channelName hasSuffix:@"Energy"]) {
            currentPowers[@"PCI"] = @(energy);
        }
    }
    
    // Calculate power (Watts) from energy delta
    if (_lastRead) {
        NSTimeInterval elapsed = [now timeIntervalSinceDate:_lastRead];
        if (elapsed > 0) {
            for (NSString *key in @[@"CPU", @"GPU", @"ANE", @"DRAM", @"PCI"]) {
                double current = [currentPowers[key] doubleValue];
                double previous = [_prevPowers[key] doubleValue];
                
                if (current > previous && previous > 0) {
                    double power = (current - previous) / elapsed; // Watts
                    
                    if ([key isEqualToString:@"CPU"]) {
                        readings.CPU = power;
                    } else if ([key isEqualToString:@"GPU"]) {
                        readings.GPU = power;
                    } else if ([key isEqualToString:@"ANE"]) {
                        readings.ANE = power;
                    } else if ([key isEqualToString:@"DRAM"]) {
                        readings.DRAM = power;
                    } else if ([key isEqualToString:@"PCI"]) {
                        readings.PCI = power;
                    }
                }
            }
        }
    }
    
    _prevPowers = [currentPowers copy];
    _lastRead = now;
    
    return readings;
}

- (void)dealloc {
    if (_subscription) {
        CFRelease(_subscription);
    }
    if (_channels) {
        CFRelease(_channels);
    }
}

@end