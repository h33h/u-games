plugins { id("com.android.application") }
android {
    namespace = "dev.ugames"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.ugames"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
