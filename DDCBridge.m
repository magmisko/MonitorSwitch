#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include "ioregistry.h"

extern IOReturn IOAVServiceReadI2C(IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);

static DDCTransport findMonitor(BOOL *ambiguous) {
    // Registry lookup also works when the monitor is absent from the online-screen list.
    io_iterator_t iterator = 0;
    DDCTransport result = {NULL, DDC_CHIP_ADDRESS_DEFAULT};
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOMobileFramebuffer"), &iterator) != KERN_SUCCESS) return result;
    io_service_t framebuffer;
    while ((framebuffer = IOIteratorNext(iterator))) {
        CFTypeRef attributes = IORegistryEntryCreateCFProperty(framebuffer,
            CFSTR("DisplayAttributes"), kCFAllocatorDefault, 0);
        NSDictionary *product = [(__bridge NSDictionary *)attributes objectForKey:@"ProductAttributes"];
        BOOL matches = [product[@"ManufacturerID"] isEqual:@"AUS"] &&
            [product[@"ProductID"] unsignedIntValue] == 12846;
        if (attributes) CFRelease(attributes);
        if (matches) {
            DisplayInfos display = {0};
            display.adapter = framebuffer;
            DDCTransport candidate = getDisplayDDCTransport(&display);
            if (candidate.service && result.service) {
                CFRelease(candidate.service);
                CFRelease(result.service);
                result.service = NULL;
                *ambiguous = YES;
                IOObjectRelease(framebuffer);
                break;
            }
            if (candidate.service) result = candidate;
        }
        IOObjectRelease(framebuffer);
    }
    IOObjectRelease(iterator);
    return result;
}

static BOOL readInput(DDCTransport transport, unsigned *value) {
    for (int attempt = 0; attempt < 3; attempt++) {
        uint8_t request[] = {0x82, 0x01, 0x60, 0x6e ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x60};
        usleep(50000);
        if (IOAVServiceWriteI2C(transport.service, transport.chipAddress, 0x51,
            request, sizeof(request)) != kIOReturnSuccess) continue;
        usleep(50000);
        if (IOAVServiceWriteI2C(transport.service, transport.chipAddress, 0x51,
            request, sizeof(request)) != kIOReturnSuccess) continue;
        usleep(100000);
        uint8_t reply[12] = {0};
        if (IOAVServiceReadI2C(transport.service, transport.chipAddress, 0x51,
            reply, sizeof(reply)) != kIOReturnSuccess) continue;
        if (getenv("MK_DDC_DEBUG")) {
            for (int i = 0; i < 12; i++) fprintf(stderr, "%02x ", reply[i]);
            fprintf(stderr, "\n");
        }
        uint8_t checksum = 0x50;
        for (int i = 0; i < 11; i++) checksum ^= reply[i];
        if (reply[0] == 0x6e && reply[1] == 0x88 && reply[2] == 0x02 &&
            reply[3] == 0 && reply[4] == 0x60 && checksum == 0) {
            *value = ((unsigned)reply[8] << 8) | reply[9];
            return YES;
        }
    }
    return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL reading = argc == 2 && strcmp(argv[1], "read") == 0;
        unsigned target = 0;
        if (argc == 3 && strcmp(argv[1], "set") == 0) {
            if (strcmp(argv[2], "19") == 0) target = 19;
            if (strcmp(argv[2], "17") == 0) target = 17;
            if (strcmp(argv[2], "18") == 0) target = 18;
            if (strcmp(argv[2], "15") == 0) target = 15;
        }
        if (!reading && !target) {
            fprintf(stderr, "Usage: ddc-bridge read | set 19|15|17|18\n");
            return 2;
        }
        BOOL ambiguous = NO;
        DDCTransport transport = findMonitor(&ambiguous);
        if (ambiguous) {
            fprintf(stderr, "Multiple ASUS PA329CV monitors are connected. This version supports one at a time.\n");
            return 6;
        }
        if (!transport.service) {
            fprintf(stderr, "ASUS PA329CV is not available through USB-C.\n");
            return 3;
        }
        if (reading) {
            unsigned value = 0;
            BOOL success = readInput(transport, &value);
            CFRelease(transport.service);
            if (!success) {
                fprintf(stderr, "The monitor did not return a valid DDC response.\n");
                return 4;
            }
            printf("%u\n", value);
            return 0;
        }
        uint8_t packet[] = {0x84, 0x03, 0x60, 0, (uint8_t)target, 0};
        packet[5] = 0x6e ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4];
        // This scaler needs the same idempotent request repeated, as in m1ddc.
        IOReturn status = kIOReturnSuccess;
        for (int attempt = 0; attempt < 2; attempt++) {
            usleep(50000);
            status = IOAVServiceWriteI2C(transport.service, transport.chipAddress,
                0x51, packet, sizeof(packet));
            if (status != kIOReturnSuccess) break;
        }
        CFRelease(transport.service);
        if (status != kIOReturnSuccess) {
            fprintf(stderr, "The monitor did not accept the input command (0x%x).\n", status);
            return 5;
        }
        printf("Sent: %u\n", target);
        return 0;
    }
}
