buildscript {
    repositories {
        google()
        mavenCentral()
        mavenLocal()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        maven { url = uri("https://repo.huaweicloud.com/repository/google/") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24")
    }
}

allprojects {
    repositories {
        maven { url = uri("https://jitpack.io") }
        google()
        mavenCentral()
        mavenLocal()
        // Official Flutter engine artifacts (REQUIRED - flutter_embedding_debug, armeabi_v7a_debug, etc.)
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        maven { url = uri("https://repo.huaweicloud.com/repository/google/") }
        maven { url = uri("https://github.com/jitsi/jitsi-maven-repository/raw/master/releases") }
        maven { url = uri("https://maven.jitsi.org/repository/maven-releases/") }
    }
}

// Contournement des tâches extractAnnotations qui échouent à télécharger des JARs lint
// (timeouts réseau). Au lieu de désactiver la tâche (ce qui casse syncLibJars),
// on remplace son action par un stub qui crée le fichier typedefs.txt attendu.
subprojects {
    afterEvaluate {
        tasks.matching { task ->
            task.name.startsWith("extract") && task.name.contains("Annotations")
        }.configureEach {
            val extractTask = this
            // Vider les actions existantes (qui essaient de télécharger des JARs)
            extractTask.actions.clear()
            // Créer les fichiers de sortie vides pour satisfaire les tâches suivantes
            extractTask.doLast {
                extractTask.outputs.files.forEach { outputFile ->
                    outputFile.parentFile?.mkdirs()
                    if (!outputFile.exists()) {
                        outputFile.createNewFile()
                    }
                }
            }
        }
        // Désactiver uniquement les tâches lint (pas de dépendances en aval)
        tasks.matching { task ->
            task.name.startsWith("lint")
        }.configureEach {
            enabled = false
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Configuration globale pour tous les projets pour éviter les conflits et erreurs réseau
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // Forcer la résolution des dépendances Jitsi récalcitrantes
    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.github.jiangdongguo.AndroidUSBCamera") {
                useTarget("com.github.jiangdongguo.AndroidUSBCamera:libausbc:3.3.3")
            }
            // Aligner toutes les dépendances Kotlin sur la version du plugin
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.24")
            }
            // Ne pas forcer org.jetbrains.kotlinx car ils ont leur propre versioning

            // Forcer les versions stables de Jetpack pour éviter l'exigence API 35/36
            if (requested.group == "androidx.core") {
                useVersion("1.13.1")
            }
            if (requested.group == "androidx.activity") {
                useVersion("1.9.3")
            }
            if (requested.group == "androidx.browser") {
                useVersion("1.8.0")
            }
            if (requested.group.startsWith("androidx.media3")) {
                useVersion("1.3.1")
            }
            if (requested.group == "androidx.navigationevent") {
                useVersion("1.0.0")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val project = this
    fun configureAndroid() {
        if (project.extensions.findByName("android") != null) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            
            // Forcer les versions du SDK pour éviter les téléchargements réseau échoués
            // On utilise try-catch pour les projets qui auraient déjà verrouillé leur config
            try {
                android.compileSdkVersion(34)
                android.defaultConfig.targetSdkVersion(34)
            } catch (e: Exception) {
                // Si c'est déjà verrouillé, on ne peut plus rien faire ici
            }

            if (android.namespace == null) {
                var foundNamespace: String? = null
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val content = manifestFile.readText()
                    val match = Regex("package=\"([^\"]+)\"").find(content)
                    if (match != null) {
                        foundNamespace = match.groupValues[1]
                    }
                }
                
                if (foundNamespace == null) {
                    foundNamespace = "com.edurdc.${project.name.replace("-", "_").replace(".", "_")}"
                }
                android.namespace = foundNamespace
            }
        }
    }

    if (project.state.executed) {
        configureAndroid()
    } else {
        project.afterEvaluate {
            configureAndroid()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
