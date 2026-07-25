.class public final Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;
.super Ljava/lang/Object;


# direct methods
.method private constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method private static isGooglePhotos()Z
    .locals 2

    invoke-static {}, Landroid/app/ActivityThread;->currentPackageName()Ljava/lang/String;

    move-result-object v0

    const-string v1, "com.google.android.apps.photos"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    return v0
.end method

.method private static setBuildField(Ljava/lang/String;Ljava/lang/String;)V
    .locals 2

    :try_start_0
    const-class v0, Landroid/os/Build;

    invoke-virtual {v0, p0}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;

    move-result-object v0

    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Ljava/lang/reflect/AccessibleObject;->setAccessible(Z)V

    const/4 v1, 0x0

    invoke-virtual {v0, v1, p1}, Ljava/lang/reflect/Field;->set(Ljava/lang/Object;Ljava/lang/Object;)V
    :try_end_10
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_10} :catch_12

    goto :cond_return

    :catch_12
    move-exception p0

    :cond_return
    return-void
.end method

.method private static spoofPixelXlBuild()V
    .locals 2

    const-string v0, "BRAND"
    const-string v1, "google"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "MANUFACTURER"
    const-string v1, "Google"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "DEVICE"
    const-string v1, "marlin"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "PRODUCT"
    const-string v1, "marlin"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "HARDWARE"
    const-string v1, "marlin"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "ID"
    const-string v1, "QP1A.191005.007.A3"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "MODEL"
    const-string v1, "Pixel XL"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "FINGERPRINT"
    const-string v1, "google/marlin/marlin:10/QP1A.191005.007.A3/5972272:user/release-keys"
    invoke-static {v0, v1}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->setBuildField(Ljava/lang/String;Ljava/lang/String;)V

    return-void
.end method


# virtual methods
.method public static hasSystemFeature(Ljava/lang/String;I)Ljava/lang/Boolean;
    .locals 1

    invoke-static {}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->isGooglePhotos()Z

    move-result p1

    if-nez p1, :cond_target

    const/4 p0, 0x0
    return-object p0

    :cond_target
    const-string v0, "com.google.android.apps.photos.NEXUS_PRELOAD"
    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result p1
    if-nez p1, :cond_enabled

    const-string v0, "com.google.android.apps.photos.nexus_preload"
    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result p1
    if-nez p1, :cond_enabled

    const-string v0, "com.google.android.feature.PIXEL_EXPERIENCE"
    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result p1
    if-nez p1, :cond_enabled

    const-string v0, "com.google.android.feature.GOOGLE_BUILD"
    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result p1
    if-nez p1, :cond_enabled

    const-string v0, "com.google.android.feature.GOOGLE_EXPERIENCE"
    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result p0
    if-nez p0, :cond_enabled

    const/4 p0, 0x0
    return-object p0

    :cond_enabled
    sget-object p0, Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;
    return-object p0
.end method

.method public static initContext(Landroid/content/Context;)V
    .locals 1

    if-eqz p0, :cond_return

    :try_start_2
    invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
    move-result-object p0

    const-string v0, "com.google.android.apps.photos"
    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result p0

    if-eqz p0, :cond_return

    invoke-static {}, Lcom/xiaomi/globalmods/framework/GooglePhotosSpoof;->spoofPixelXlBuild()V
    :try_end_14
    .catch Ljava/lang/Throwable; {:try_start_2 .. :try_end_14} :catch_15

    goto :cond_return

    :catch_15
    move-exception p0

    :cond_return
    return-void
.end method
