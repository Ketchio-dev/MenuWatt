#include "CIOReport.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>

// SMC struct layout — must match kernel expectations (natural C alignment, 80 bytes).

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    uint8_t        vers[6];
    uint8_t        pLimitData[16];
    SMCKeyInfoData keyInfo;
    uint8_t        result;
    uint8_t        status;
    uint8_t        data8;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCKeyData;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) |
           ((uint32_t)s[2] << 8)  | (uint32_t)s[3];
}

static io_connect_t openSMC(void) {
    io_connect_t conn = 0;
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    return conn;
}

static double readFloat(io_connect_t conn, const char *key) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t kr;

    // Step 1: getKeyInfo (data8 = 9)
    input.key = fourcc(key);
    input.data8 = 9;
    kr = IOConnectCallStructMethod(conn, 2, &input, sizeof(input), &output, &outSize);
    if (kr != KERN_SUCCESS) return -1;

    uint32_t dataSize = output.keyInfo.dataSize;
    if (dataSize != 4) return -1;

    // Step 2: readKey (data8 = 5)
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    outSize = sizeof(SMCKeyData);
    input.key = fourcc(key);
    input.data8 = 5;
    input.keyInfo.dataSize = dataSize;
    kr = IOConnectCallStructMethod(conn, 2, &input, sizeof(input), &output, &outSize);
    if (kr != KERN_SUCCESS) return -1;

    float value;
    memcpy(&value, output.bytes, 4);
    return (double)value;
}

SMCPowerReading SMCReadPower(void) {
    SMCPowerReading reading = { -1, -1 };

    io_connect_t conn = openSMC();
    if (!conn) return reading;

    reading.systemPower = readFloat(conn, "PSTR");
    reading.deliveryRate = readFloat(conn, "PDTR");

    IOServiceClose(conn);
    return reading;
}
