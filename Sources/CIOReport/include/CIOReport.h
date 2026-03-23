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

#endif /* CIOReport_h */
