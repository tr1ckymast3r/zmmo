# ZMMO Helper: ZmmoProps.smali — Property lookup with spoof override
# Target: This is a NEW smali file to be added: zmmo/ZmmoProps.smali
#
# This helper reads a system property. If persist.zmmo.<prop> is set,
# it returns the spoofed value. Otherwise returns the real one.
#
# Used by: Build.smali <clinit>, WifiManager, BluetoothAdapter, etc.

.class public Lzmmo/ZmmoProps;
.super Ljava/lang/Object;

# get(String realProp) → String
# Reads persist.zmmo.<prop> first, falls back to realProp.
.method public static get(Ljava/lang/String;)Ljava/lang/String;
    .locals 4

    # Build the spoof key: "persist.zmmo." + prop_name
    new-instance v0, Ljava/lang/StringBuilder;
    const-string v1, "persist.zmmo."
    invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    # Extract short name from full prop (e.g., "ro.product.model" → "model")
    # For simplicity: use the last segment after the last dot
    const-string v1, "."
    invoke-virtual {p0, v1}, Ljava/lang/String;->lastIndexOf(Ljava/lang/String;)I
    move-result v2
    add-int/lit8 v2, v2, 0x1
    invoke-virtual {p0, v2}, Ljava/lang/String;->substring(I)Ljava/lang/String;
    move-result-object v3
    invoke-virtual {v0, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v0

    # Try the spoofed value
    const/4 v1, 0x0
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    move-result-object v2

    # If not null/empty, return it
    invoke-static {v2}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
    move-result v3
    if-nez v3, :zmmo_return_spoofed

    # Fallback: real prop
    invoke-static {p0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    move-result-object v2

    :zmmo_return_spoofed
    return-object v2
.end method

# getLong(String prop) → long — for Build.TIME
.method public static getLong(Ljava/lang/String;)J
    .locals 2

    invoke-static {p0}, Lzmmo/ZmmoProps;->get(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0

    if-nez v0, :zmmo_default
    invoke-static {v0}, Ljava/lang/Long;->parseLong(Ljava/lang/String;)J
    move-result-wide v0
    return-wide v0

    :zmmo_default
    const-wide/16 v0, 0x0
    return-wide v0
.end method
