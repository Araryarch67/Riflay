allprojects {
    repositories {
        google()
        mavenCentral()
        // libusbdac (Direct USB) is published there from its release tags, and only there.
        maven("https://jitpack.io") {
            content { includeGroup("com.github.ostrichbat2k") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
// Plugins still on an older compileSdk than their own dependencies need (onnxruntime, for Poster's cutout: 33,
// while its androidx libraries ask for 34): built against the app's.
subprojects {
    if (name == "onnxruntime") {
        // After its own build script, which sets 33.
        val raise = { extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 36 }
        if (state.executed) raise() else afterEvaluate { raise() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
