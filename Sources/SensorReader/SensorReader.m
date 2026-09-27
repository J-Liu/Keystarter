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

typedef IOReportSubscriptionRef (*IOReportCreateSubscriptionFunc)(void *allocator, CFMutableDictionaryRef channels, CFMutableDictionaryRef *subscribed, uint64_t flags, CFTypeRef error);
typedef CFMutableDictionaryRef (*IOReportCopyChannelsInGroupFunc)(CFStringRef group, CFStringRef subGroup, uint64_t a, uint64_t b, uint64_t c);
typedef void (*IOReportMergeChannelsFunc)(CFMutableDictionaryRef a, CFDictionaryRef b, CFTypeRef null);
typedef int64_t (*IOReportSimpleGetIntegerValueFunc)(CFDictionaryRef channel, int sample_idx);
typedef CFStringRef (*IOReportChannelGetGroupFunc)(CFDictionaryRef channel);
typedef CFStringRef (*IOReportChannelGetChannelNameFunc)(CFDictionaryRef channel);
typedef CFStringRef (*IOReportChannelGetUnitLabelFunc)(CFDictionaryRef channel);
typedef CFDictionaryRef (*IOReportCreateSamplesFunc)(IOReportSubscriptionRef subscription, CFMutableDictionaryRef channels, CFDictionaryRef previous);

// Static function pointers
static IOHIDEventSystemClientCreateFunc _IOHIDEventSystemClientCreate = NULL;
static IOHIDEventSystemClientSetMatchingFunc _IOHIDEventSystemClientSetMatching = NULL;
static IOHIDEventSystemClientCopyServicesFunc _IOHIDEventSystemClientCopyServices = NULL;
static IOHIDServiceClientCopyPropertyFunc _IOHIDServiceClientCopyProperty = NULL;
static IOHIDServiceClientCopyEventFunc _IOHIDServiceClientCopyEvent = NULL;
static IOHIDEventGetFloatValueFunc _IOHIDEventGetFloatValue = NULL;
static IOHIDEventFieldBaseFunc _IOHIDEventFieldBase = NULL;

static IOReportCreateSubscriptionFunc _IOReportCreateSubscription = NULL;
static IOReportCopyChannelsInGroupFunc _IOReportCopyChannelsInGroup = NULL;
static IOReportMergeChannelsFunc _IOReportMergeChannels = NULL;
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
    if (!handle) {
        fprintf(stderr, "[SensorReader] dlopen failed\n");
        return;
    }
    
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
    _IOReportCopyChannelsInGroup = (IOReportCopyChannelsInGroupFunc)dlsym(handle, "IOReportCopyChannelsInGroup");
    _IOReportMergeChannels = (IOReportMergeChannelsFunc)dlsym(handle, "IOReportMergeChannels");
    _IOReportSimpleGetIntegerValue = (IOReportSimpleGetIntegerValueFunc)dlsym(handle, "IOReportSimpleGetIntegerValue");
    _IOReportChannelGetGroup = (IOReportChannelGetGroupFunc)dlsym(handle, "IOReportChannelGetGroup");
    _IOReportChannelGetChannelName = (IOReportChannelGetChannelNameFunc)dlsym(handle, "IOReportChannelGetChannelName");
    _IOReportChannelGetUnitLabel = (IOReportChannelGetUnitLabelFunc)dlsym(handle, "IOReportChannelGetUnitLabel");
    _IOReportCreateSamples = (IOReportCreateSamplesFunc)dlsym(handle, "IOReportCreateSamples");
    
    dlclose(handle);
    _functionsLoaded = YES;
    
    fprintf(stderr, "[SensorReader] HID: create=%p, copyServices=%p\n",
            _IOHIDEventSystemClientCreate, _IOHIDEventSystemClientCopyServices);
    fprintf(stderr, "[SensorReader] IOReport: copyChannels=%p, createSamples=%p\n",
            _IOReportCopyChannelsInGroup, _IOReportCreateSamples);
}

// Power readings implementation
@implementation PowerReadings
@end

@implementation SensorReader {
    IOReportSubscriptionRef _subscription;
    CFMutableDictionaryRef _channels;
    NSMutableDictionary *_prevPowers;
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
    // Different sensor types have different usage page/usage
    // Temperature: page=0xff00, usage=0x0005
    // Current: page=0xff08, usage=0x0002
    // Voltage: page=0xff08, usage=0x0003
    int32_t usagePage, usage;
    switch (type) {
        case SensorTypeTemperature:
            usagePage = 0xff00;
            usage = 0x0005;
            break;
        case SensorTypeCurrent:
            usagePage = 0xff08;
            usage = 0x0002;
            break;
        case SensorTypeVoltage:
            usagePage = 0xff08;
            usage = 0x0003;
            break;
        default:
            usagePage = 0xff00;
            usage = 0x0005;
            break;
    }
    
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(usagePage),
        @"PrimaryUsage": @(usage)
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
        int32_t eventType;
        switch (type) {
            case SensorTypeTemperature:
                eventType = 15; // kIOHIDEventTypeTemperature
                break;
            case SensorTypeVoltage:
            case SensorTypeCurrent:
                eventType = 25; // kIOHIDEventTypePower
                break;
            default:
                eventType = 15;
                break;
        }
        
        IOHIDEventRef event = _IOHIDServiceClientCopyEvent(service, eventType, 0, 0);
        if (!event) {
            continue;
        }
        
        // Extract value - field is eventType << 16 (IOHIDEventFieldBase macro)
        int32_t field = eventType << 16;
        double value = _IOHIDEventGetFloatValue(event, field);
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
        _prevPowers = [NSMutableDictionary dictionaryWithDictionary:@{
            @"CPU": @0,
            @"GPU": @0,
            @"ANE": @0,
            @"DRAM": @0,
            @"PCI": @0
        }];
    }
    return self;
}

- (void)setupPowerMonitoring {
    loadPrivateFunctions();
    
    if (!_IOReportCopyChannelsInGroup || !_IOReportCreateSubscription) {
        NSLog(@"IOReport functions not found");
        return;
    }
    
    // Get channels for energy monitoring
    CFDictionaryRef rawChannels = _IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (!rawChannels) {
        NSLog(@"Failed to get Energy Model channels");
        return;
    }
    
    // Create a mutable copy (like Stats does)
    CFIndex size = CFDictionaryGetCount(rawChannels);
    _channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, size, rawChannels);
    CFRelease(rawChannels);
    
    if (!_channels) {
        NSLog(@"Failed to create mutable copy of channels");
        return;
    }
    
    // Check channels count
    NSDictionary *chanDict = (__bridge NSDictionary *)_channels;
    NSArray *chanList = chanDict[@"IOReportChannels"];
    NSLog(@"Found %lu IOReport channels", (unsigned long)[chanList count]);
    
    // Create subscription
    CFMutableDictionaryRef subscribedDict = NULL;
    _subscription = _IOReportCreateSubscription(NULL, _channels, &subscribedDict, 0, NULL);
    
    if (!_subscription) {
        NSLog(@"Failed to create IOReport subscription");
        CFRelease(_channels);
        _channels = NULL;
        return;
    }
    
    // Don't replace channels with subscribedDict (Stats doesn't do this)
    if (subscribedDict) {
        CFRelease(subscribedDict);
    }
    
    // Initialize previous powers
    _prevPowers = [@{
        @"CPU": @0,
        @"GPU": @0,
        @"ANE": @0,
        @"DRAM": @0,
        @"PCI": @0
    } mutableCopy];
    
    NSLog(@"Power monitoring ready");
}

- (PowerReadings *)readPower {
    PowerReadings *readings = [[PowerReadings alloc] init];
    
    if (!_subscription || !_channels || !_IOReportCreateSamples ||
        !_IOReportChannelGetGroup || !_IOReportChannelGetChannelName ||
        !_IOReportChannelGetUnitLabel || !_IOReportSimpleGetIntegerValue) {
        return readings;
    }
    
    // Get current samples
    CFDictionaryRef samples = _IOReportCreateSamples(_subscription, _channels, NULL);
    if (!samples) {
        return readings;
    }
    
    NSDictionary *sampleDict = (__bridge_transfer NSDictionary *)samples;
    NSArray *channels = sampleDict[@"IOReportChannels"];
    if (!channels) {
        return readings;
    }
    
    NSDate *now = [NSDate date];
    NSMutableDictionary *currentPowers = [NSMutableDictionary dictionary];
    
    // Accumulate sub-channel energies (like Stats does)
    double eaccCPU = 0, pacc0CPU = 0, pacc1CPU = 0;
    double cpuAggregate = 0, gpuEnergy = 0, aneEnergy = 0, dramEnergy = 0, pciEnergy = 0;
    BOOL hasSubChannels = NO;
    
    // Read energy values
    for (id item in channels) {
        CFDictionaryRef channel = (__bridge CFDictionaryRef)item;
        
        CFStringRef groupCF = _IOReportChannelGetGroup(channel);
        if (!groupCF) continue;
        NSString *group = (__bridge NSString *)groupCF;
        if (![group isEqualToString:@"Energy Model"]) {
            continue;
        }
        
        CFStringRef channelNameCF = _IOReportChannelGetChannelName(channel);
        CFStringRef unitCF = _IOReportChannelGetUnitLabel(channel);
        if (!channelNameCF || !unitCF) continue;
        
        NSString *channelName = (__bridge NSString *)channelNameCF;
        NSString *unit = (__bridge NSString *)unitCF;
        int64_t value = _IOReportSimpleGetIntegerValue(channel, 0);
        
        // Convert to Joules
        double energy = 0;
        if ([unit isEqualToString:@"mJ"]) {
            energy = value / 1e3;
        } else if ([unit isEqualToString:@"µJ"] || [unit isEqualToString:@"uJ"]) {
            energy = value / 1e6;
        } else if ([unit isEqualToString:@"nJ"]) {
            energy = value / 1e9;
        }
        
        // Accumulate sub-channels for CPU (these update individually)
        if ([channelName isEqualToString:@"EACC_CPU"]) {
            eaccCPU = energy;
            hasSubChannels = YES;
        } else if ([channelName isEqualToString:@"PACC0_CPU"]) {
            pacc0CPU = energy;
            hasSubChannels = YES;
        } else if ([channelName isEqualToString:@"PACC1_CPU"]) {
            pacc1CPU = energy;
            hasSubChannels = YES;
        } else if ([channelName isEqualToString:@"CPU Energy"]) {
            cpuAggregate = energy; // Fallback if sub-channels not available
        } else if ([channelName isEqualToString:@"GPU Energy"]) {
            gpuEnergy = energy;
        } else if ([channelName hasPrefix:@"ANE"]) {
            aneEnergy = energy;
        } else if ([channelName hasPrefix:@"DRAM"]) {
            dramEnergy = energy;
        } else if ([channelName hasPrefix:@"PCI"] && [channelName hasSuffix:@"Energy"]) {
            pciEnergy = energy;
        }
    }
    
    // Use sub-channel sum if available (E-core + P-core clusters), otherwise fall back to aggregate
    if (hasSubChannels) {
        currentPowers[@"CPU"] = @(eaccCPU + pacc0CPU + pacc1CPU);
    } else {
        currentPowers[@"CPU"] = @(cpuAggregate);
    }
    currentPowers[@"GPU"] = @(gpuEnergy);
    currentPowers[@"ANE"] = @(aneEnergy);
    currentPowers[@"DRAM"] = @(dramEnergy);
    currentPowers[@"PCI"] = @(pciEnergy);
    
    // Debug: log energy values (comment out in production)
    // NSLog(@"[SensorReader] CPU Energy: EACC=%.2f PACC0=%.2f PACC1=%.2f", eaccCPU, pacc0CPU, pacc1CPU);
    
    // Calculate power from energy delta
    if (_lastRead) {
        NSTimeInterval elapsed = [now timeIntervalSinceDate:_lastRead];
        
        double cpuCurrent = [currentPowers[@"CPU"] doubleValue];
        double cpuPrevious = [_prevPowers[@"CPU"] doubleValue];
        double gpuCurrent = [currentPowers[@"GPU"] doubleValue];
        double gpuPrevious = [_prevPowers[@"GPU"] doubleValue];
        
        
        if (elapsed > 0 && cpuPrevious > 0) {
            double cpuDelta = cpuCurrent - cpuPrevious;
            if (cpuDelta > 0) {
                readings.CPU = cpuDelta / elapsed;
            }
        }
        if (elapsed > 0 && gpuPrevious > 0) {
            double gpuDelta = gpuCurrent - gpuPrevious;
            if (gpuDelta > 0) {
                readings.GPU = gpuDelta / elapsed;
            }
        }
        
        // Other components
        for (NSString *key in @[@"ANE", @"DRAM", @"PCI"]) {
            double current = [currentPowers[key] doubleValue];
            double previous = [_prevPowers[key] doubleValue];
            if (elapsed > 0 && previous > 0) {
                double delta = current - previous;
                if (delta > 0) {
                    double power = delta / elapsed;
                    if ([key isEqualToString:@"ANE"]) readings.ANE = power;
                    else if ([key isEqualToString:@"DRAM"]) readings.DRAM = power;
                    else if ([key isEqualToString:@"PCI"]) readings.PCI = power;
                }
            }
        }
    }
    
    // Update previous values
    [_prevPowers setDictionary:currentPowers];
    _lastRead = now;
    
    return readings;
}

- (void)dealloc {
}

@end