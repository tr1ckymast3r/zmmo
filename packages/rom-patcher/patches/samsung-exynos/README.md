# ZMMO Samsung Exynos Patch: SamsungRIL wrapper hooks
# Target: Samsung Galaxy S8/S9/S10/S20 (Exynos SoC) on LineageOS
# Android 10-12
#
# Samsung devices have a custom RIL layer (SamsungRIL.java) 
# that wraps AOSP RILJ and may bypass our standard hooks.
# This patch hooks SamsungRIL directly.

# === Patch: SamsungRIL.smali ===
# Target: com/android/internal/telephony/SamsungRIL.smali
# Method: getDeviceIdentity(Landroid/os/Message;)V
#
# On Samsung, getDeviceIdentity() fetches IMEI from CP directly.
# The standard TelephonyManager.getDeviceId() route may still be caught
# by our framework.jar patch, but apps using Samsung-specific APIs 
# (like *#06#, Samsung Device Care) will bypass it.
#
# This patch intercepts SamsungRIL at the source.

.method public getDeviceIdentity(Landroid/os/Message;)V
    .locals 4

    # Check if spoof is active
    const-string v0, "persist.zmmo.imei_slot1"
    invoke-static {v0}, Landroid/os/SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1

    invoke-static {v1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
    move-result v2
    if-eqz v2, :zmmo_real

    # Spoof active — return immediately with fake IMEI
    invoke-direct {p0, v1, p1}, Lcom/android/internal/telephony/SamsungRIL;->zmmoSendSpoofedIdentity(Ljava/lang/String;Landroid/os/Message;)V
    return-void

    :zmmo_real
    # Original: invoke CP command to get real IMEI
    # (falls through to existing SamsungRIL implementation)
.end method

# === Additional Samsung-specific hooks ===

# SamsungServiceStateTracker — may override operator display
# Target: com/android/internal/telephony/samsung/SamsungServiceStateTracker.smali
# Not always present — only on ROMs with Samsung blobs loaded

# SamsungPhoneInterfaceManager — used by Samsung Dialer/Contacts
# Target: com/samsung/android/telephony/SamsungPhoneInterfaceManager.smali  
# Methods: getLine1Number(), getDeviceId()

# === Samsung build.prop detection patterns ===
# S8:   dreamlte/dream2lte   (Exynos 8895)
# S9:   starlte/star2lte      (Exynos 9810)
# S10:  beyond0lte/beyond1lte/beyond2lte (Exynos 9820)
# S20:  x1s/x1q               (Exynos 990)
# Note: Galaxy S line uses "x1q" codename pattern for Exynos
