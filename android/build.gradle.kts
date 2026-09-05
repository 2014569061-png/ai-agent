import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

    // 统一 Java/Kotlin JVM target 到 17，解决部分插件内部
    // Java(1.8) 与 Kotlin(21) 编译目标不一致导致的构建失败。
    afterEvaluate {
        tasks.withType(JavaCompile::class.java).configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType(KotlinCompile::class.java).configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
        // 强制所有插件 compileSdk >= 37（修复 super_native_extensions 等
        // 旧插件硬编码 compileSdk 31 与 androidx 33+ 依赖的冲突）。
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt is com.android.build.api.dsl.CommonExtension<*, *, *, *, *, *>) {
                val current = androidExt.compileSdk ?: 0
                if (current < 37) {
                    androidExt.compileSdk = 37
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}