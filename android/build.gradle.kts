allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force all subprojects (including Flutter plugins like receive_sharing_intent) to use
// consistent Java/Kotlin JVM targets.  Without this, plugins that mix Java 1.8 compile
// options with Kotlin JVM target 21 cause Gradle to fail with:
//   "Inconsistent JVM-target compatibility detected for tasks
//    compileDebugJavaWithJavac (1.8) and compileDebugKotlin (21)."
subprojects {
    afterEvaluate {
        // Align Java compile options
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        // Align Kotlin JVM target for every Kotlin compile task in every subproject
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
