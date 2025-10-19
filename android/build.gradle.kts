allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://transistorsoft.github.io/maven")
        }
        // ADD THIS - background_fetch local libs
        maven {
            url = uri("${project(":background_fetch").projectDir}/libs")
        }
    }
}

// ... rest of your file remains the same

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
