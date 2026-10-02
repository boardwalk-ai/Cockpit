allprojects {
    repositories {
        google()
        mavenCentral()
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
// file_picker 8 still compiles against android-34, but plugins it depends on
// now require 36. Build every Android library plugin against 36.
subprojects {
    val useSdk36 = {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
            ?.let { it.compileSdk = 36 }
    }
    if (state.executed) useSdk36() else afterEvaluate { useSdk36() }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
