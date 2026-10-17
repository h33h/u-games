plugins { id("com.android.application") }
android {
    namespace = "dev.ugames"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.ugames"
        minSdk = 24
        targetSdk = 36
        versionCode = providers.environmentVariable("UGAMES_BUILD_NUMBER").orElse("1").get().toInt()
        versionName = providers.environmentVariable("UGAMES_VERSION").orElse("0.1.0").get()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    val releaseKeystore = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull
    if (releaseKeystore != null) {
        signingConfigs {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS").get()
                keyPassword = providers.environmentVariable("ANDROID_KEY_PASSWORD").get()
            }
        }
        buildTypes.getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets.getByName("androidTest").assets.srcDir("../../shared/fixtures")
}
val sharedAssets by tasks.registering(Exec::class) {
    workingDir = rootProject.projectDir.parentFile
    commandLine("node", "scripts/build-shared.cjs")
    inputs.files(
        "../../shared/ad-adapter.js",
        "../../shared/offline-games.js",
        "../../shared/offline-catalog.js",
        "../../shared/offline-catalog.html",
        "../../shared/ad-countdowns.js",
        "../../shared/ad-provider-availability.js",
        "../../shared/construct-ad-guard.js",
        "../../shared/ad-rules.json",
        "../../shared/branding.json",
        "../../shared/portal-theme.js",
        "../../shared/portal-theme.css",
        "../../scripts/build-shared.cjs"
    )
    inputs.dir("../../shared/assets")
    outputs.dir("src/main/assets/ugames")
}
tasks.named("preBuild") { dependsOn(sharedAssets) }
dependencies {
    implementation("androidx.activity:activity:1.10.1")
    implementation("androidx.webkit:webkit:1.17.1")
    implementation("org.brotli:dec:0.1.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
