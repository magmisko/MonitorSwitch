#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <mach-o/dyld.h>
#include "ioregistry.h"

extern IOReturn IOAVServiceReadI2C(IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);

typedef struct { DDCTransport transport; NSDictionary *profile; BOOL ambiguous; } Monitor;

static NSArray *loadProfiles(void) {
    char path[PATH_MAX]; uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size)) return nil;
    NSString *folder = [[@(path) stringByResolvingSymlinksInPath] stringByDeletingLastPathComponent];
    NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"monitors.json"]];
    if (!data) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]] || [root[@"schemaVersion"] intValue] != 1) return nil;
    NSArray *profiles = root[@"monitors"];
    return [profiles isKindOfClass:[NSArray class]] ? profiles : nil;
}

static Monitor findMonitor(NSArray *profiles) {
    Monitor result = {0};
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebuffer"), &iterator)) return result;
    io_service_t framebuffer;
    while ((framebuffer = IOIteratorNext(iterator))) {
        CFTypeRef attributes = IORegistryEntryCreateCFProperty(framebuffer, CFSTR("DisplayAttributes"), kCFAllocatorDefault, 0);
        NSDictionary *product = nil;
        if (attributes && CFGetTypeID(attributes) == CFDictionaryGetTypeID()) product = [(__bridge NSDictionary *)attributes objectForKey:@"ProductAttributes"];
        for (NSDictionary *profile in profiles) {
            if (![product[@"ManufacturerID"] isEqual:profile[@"manufacturer"]] ||
                ![product[@"ProductID"] isEqual:profile[@"productID"]]) continue;
            DisplayInfos display = {0}; display.adapter = framebuffer;
            DDCTransport candidate = getDisplayDDCTransport(&display);
            if (!candidate.service) continue;
            if (result.transport.service) {
                CFRelease(candidate.service); CFRelease(result.transport.service);
                result.transport.service = NULL; result.ambiguous = YES;
            } else { result.transport = candidate; result.profile = profile; }
            break;
        }
        if (attributes) CFRelease(attributes);
        IOObjectRelease(framebuffer);
        if (result.ambiguous) break;
    }
    IOObjectRelease(iterator);
    return result;
}

static NSArray *listDisplays(void) {
    NSMutableArray *displays = [NSMutableArray array];
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebuffer"), &iterator)) return displays;
    io_service_t framebuffer;
    while ((framebuffer = IOIteratorNext(iterator))) {
        DisplayInfos display = {0}; display.adapter = framebuffer;
        DDCTransport transport = getDisplayDDCTransport(&display);
        if (transport.service) {
            CFTypeRef attributes = IORegistryEntryCreateCFProperty(framebuffer, CFSTR("DisplayAttributes"), kCFAllocatorDefault, 0);
            if (attributes && CFGetTypeID(attributes) == CFDictionaryGetTypeID()) {
                NSDictionary *product = [(__bridge NSDictionary *)attributes objectForKey:@"ProductAttributes"];
                if (product[@"ManufacturerID"] && product[@"ProductID"]) {
                    [displays addObject:@{@"manufacturer": product[@"ManufacturerID"], @"productID": product[@"ProductID"], @"name": product[@"ProductName"] ?: @"External display"}];
                }
            }
            if (attributes) CFRelease(attributes);
            CFRelease(transport.service);
        }
        IOObjectRelease(framebuffer);
    }
    IOObjectRelease(iterator);
    return displays;
}

static BOOL readFeature(DDCTransport t, uint8_t code, unsigned *value, unsigned *maximum) {
    for (int attempt = 0; attempt < 3; attempt++) {
        uint8_t request[] = {0x82, 0x01, code, (uint8_t)(0x6e ^ 0x51 ^ 0x82 ^ 0x01 ^ code)};
        usleep(50000);
        if (IOAVServiceWriteI2C(t.service, t.chipAddress, 0x51, request, sizeof(request))) continue;
        usleep(50000);
        if (IOAVServiceWriteI2C(t.service, t.chipAddress, 0x51, request, sizeof(request))) continue;
        usleep(100000);
        uint8_t reply[12] = {0};
        if (IOAVServiceReadI2C(t.service, t.chipAddress, 0x51, reply, sizeof(reply))) continue;
        uint8_t checksum = 0x50;
        for (int i = 0; i < 11; i++) checksum ^= reply[i];
        if (reply[0] == 0x6e && reply[1] == 0x88 && reply[2] == 0x02 && reply[3] == 0 && reply[4] == code && checksum == 0) {
            *value = ((unsigned)reply[8] << 8) | reply[9];
            *maximum = ((unsigned)reply[6] << 8) | reply[7];
            return YES;
        }
    }
    return NO;
}

static BOOL writeFeature(DDCTransport t, uint8_t code, unsigned value) {
    uint8_t packet[] = {0x84, 0x03, code, (uint8_t)(value >> 8), (uint8_t)value, 0};
    packet[5] = 0x6e ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4];
    for (int attempt = 0; attempt < 2; attempt++) {
        usleep(50000);
        if (IOAVServiceWriteI2C(t.service, t.chipAddress, 0x51, packet, sizeof(packet))) return NO;
    }
    return YES;
}

static void printJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, stdout); putchar('\n');
}

static NSDictionary *readControl(DDCTransport t, uint8_t code) {
    unsigned value = 0, maximum = 0;
    if (!readFeature(t, code, &value, &maximum) || !maximum || value > maximum) return @{@"available": @NO};
    return @{@"available": @YES, @"value": @(value), @"maximum": @(maximum)};
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "list") == 0) { printJSON(listDisplays()); return 0; }
        BOOL info = argc == 2 && strcmp(argv[1], "info") == 0;
        BOOL controls = argc == 3 && strcmp(argv[1], "controls") == 0;
        BOOL setting = argc == 5 && strcmp(argv[1], "set") == 0;
        if (!info && !controls && !setting) {
            fprintf(stderr, "Usage: ddc-bridge list | info | controls PROFILE | set PROFILE input|brightness|volume VALUE\n"); return 2;
        }
        NSArray *profiles = loadProfiles();
        if (!profiles.count) { fprintf(stderr, "The monitor profile catalog is missing or invalid.\n"); return 2; }
        Monitor m = findMonitor(profiles);
        if (m.ambiguous) { fprintf(stderr, "Multiple supported monitors are connected. This version supports one at a time.\n"); return 6; }
        if (!m.transport.service) { fprintf(stderr, "No supported monitor is available. Enable DDC/CI or request a profile on GitHub.\n"); return 3; }
        int result = 0;
        if (!info && ![m.profile[@"id"] isEqual:@(argv[2])]) {
            fprintf(stderr, "The connected monitor changed. Reopen the app menu before trying again.\n"); result = 3;
        } else if (info) {
            unsigned value = 0, maximum = 0;
            BOOL ok = readFeature(m.transport, 0x60, &value, &maximum);
            printJSON(@{@"profile": m.profile[@"id"], @"model": m.profile[@"name"], @"input": ok ? @(value) : (id)[NSNull null]});
        } else if (controls) {
            NSMutableDictionary *values = [NSMutableDictionary dictionary];
            for (NSString *name in m.profile[@"controls"]) {
                uint8_t code = [name isEqual:@"brightness"] ? 0x10 : [name isEqual:@"volume"] ? 0x62 : 0;
                if (code) values[name] = readControl(m.transport, code);
            }
            printJSON(values);
        } else {
            NSString *feature = @(argv[3]);
            char *end = NULL; errno = 0;
            unsigned long parsed = strtoul(argv[4], &end, 10);
            uint8_t code = [feature isEqual:@"input"] ? 0x60 : [feature isEqual:@"brightness"] ? 0x10 : [feature isEqual:@"volume"] ? 0x62 : 0;
            BOOL allowed = code && argv[4][0] >= '0' && argv[4][0] <= '9' && end && *end == 0 && !errno && parsed <= 65535;
            if (code == 0x60) {
                BOOL validPort = NO;
                for (NSDictionary *port in m.profile[@"ports"]) if ([port[@"code"] unsignedIntValue] == parsed) validPort = YES;
                allowed = allowed && validPort;
            } else if (allowed) {
                allowed = [m.profile[@"controls"] containsObject:feature];
                unsigned current = 0, maximum = 0;
                allowed = allowed && readFeature(m.transport, code, &current, &maximum) && maximum > 0 && parsed <= maximum;
            }
            if (!allowed) { fprintf(stderr, "This control or value is not supported by the selected monitor profile.\n"); result = 2; }
            else if (!writeFeature(m.transport, code, (unsigned)parsed)) { fprintf(stderr, "The monitor did not accept the command.\n"); result = 5; }
            else if (code == 0x60) { printJSON(@{@"sent": @(parsed)}); }
            else {
                NSDictionary *value = nil;
                for (int attempt = 0; attempt < 2; attempt++) {
                    usleep(400000); value = readControl(m.transport, code);
                    if ([value[@"available"] boolValue] && [value[@"value"] unsignedIntValue] == parsed) break;
                }
                if (![value[@"available"] boolValue] || [value[@"value"] unsignedIntValue] != parsed) {
                    fprintf(stderr, "The monitor did not apply the setting. Check its HDR or picture mode, then reopen Controls.\n"); result = 7;
                } else printJSON(value);
            }
        }
        CFRelease(m.transport.service);
        return result;
    }
}
