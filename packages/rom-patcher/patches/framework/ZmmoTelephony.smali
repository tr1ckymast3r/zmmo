# ZMMO Helper: ZmmoTelephony.smali — Real telephony calls (bypass hooks)
# Target: NEW file: zmmo/ZmmoTelephony.smali
#
# Provides direct access to real ITelephony methods so our hooks
# can still fall through to real values when no spoof is set.

.class public Lzmmo/ZmmoTelephony;
.super Ljava/lang/Object;

# getRealDeviceId(TelephonyManager tm, int slot) → String
.method public static getRealDeviceId(I)Ljava/lang/String;
    .locals 5

    :try_start_zmmo
    const-string v0, "phone"
    invoke-static {v0}, Landroid/os/ServiceManager;->getService(Ljava/lang/String;)Landroid/os/IBinder;
    move-result-object v1

    invoke-static {v1}, Lcom/android/internal/telephony/ITelephony$Stub;->asInterface(Landroid/os/IBinder;)Lcom/android/internal/telephony/ITelephony;
    move-result-object v2

    invoke-interface {v2, p0}, Lcom/android/internal/telephony/ITelephony;->getDeviceId(I)Ljava/lang/String;
    move-result-object v3
    return-object v3
    :try_end_zmmo
    .catch Ljava/lang/Exception; {:try_start_zmmo .. :try_end_zmmo} :zmmo_error

    :zmmo_error
    const/4 v4, 0x0
    return-object v4
.end method

# getRealImei(int slot) → String
.method public static getRealImei(I)Ljava/lang/String;
    .locals 5

    :try_start_zmmo
    const-string v0, "phone"
    invoke-static {v0}, Landroid/os/ServiceManager;->getService(Ljava/lang/String;)Landroid/os/IBinder;
    move-result-object v1

    invoke-static {v1}, Lcom/android/internal/telephony/ITelephony$Stub;->asInterface(Landroid/os/IBinder;)Lcom/android/internal/telephony/ITelephony;
    move-result-object v2

    invoke-interface {v2, p0}, Lcom/android/internal/telephony/ITelephony;->getImeiForSlot(I)Ljava/lang/String;
    move-result-object v3
    return-object v3
    :try_end_zmmo
    .catch Ljava/lang/Exception; {:try_start_zmmo .. :try_end_zmmo} :zmmo_error

    :zmmo_error
    const/4 v4, 0x0
    return-object v4
.end method

# getRealMeid(int slot) → String
.method public static getRealMeid(I)Ljava/lang/String;
    .locals 5

    :try_start_zmmo
    const-string v0, "phone"
    invoke-static {v0}, Landroid/os/ServiceManager;->getService(Ljava/lang/String;)Landroid/os/IBinder;
    move-result-object v1

    invoke-static {v1}, Lcom/android/internal/telephony/ITelephony$Stub;->asInterface(Landroid/os/IBinder;)Lcom/android/internal/telephony/ITelephony;
    move-result-object v2

    invoke-interface {v2, p0}, Lcom/android/internal/telephony/ITelephony;->getMeidForSlot(I)Ljava/lang/String;
    move-result-object v3
    return-object v3
    :try_end_zmmo
    .catch Ljava/lang/Exception; {:try_start_zmmo .. :try_end_zmmo} :zmmo_error

    :zmmo_error
    const/4 v4, 0x0
    return-object v4
.end method
