#ifndef CIOReport_h
#define CIOReport_h

/// Power readings from the SMC (System Management Controller).
typedef struct {
    /// System Total Power in watts (SMC key "PSTR"). Negative if unavailable.
    double systemPower;
    /// DC-In / Delivery Rate in watts (SMC key "PDTR"). Negative if unavailable.
    double deliveryRate;
} SMCPowerReading;

/// Read PSTR and PDTR from the SMC in a single connection.
/// Fields are negative when a key is unavailable.
SMCPowerReading SMCReadPower(void);

/// Fan readings from the SMC. Up to two fans. Negative fields mean unavailable.
typedef struct {
    double fan0Rpm;
    double fan0MaxRpm;
    double fan1Rpm;
    double fan1MaxRpm;
} SMCFanReading;

/// Read fan speeds (F0Ac/F0Mx/F1Ac/F1Mx) from the SMC.
/// Negative fields indicate the key is unavailable (e.g. fanless Macs).
SMCFanReading SMCReadFans(void);

#endif /* CIOReport_h */
