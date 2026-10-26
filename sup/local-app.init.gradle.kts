// Gradle init-script for su-se-bakover: registrerer :web-regresjonstest:supLocal
// som kjører LocalApplicationWithTestdata, uten endringer i repoet.
// Brukes av `sup backend start`:
//   ./gradlew --init-script <denne fila> :web-regresjonstest:supLocal

allprojects {
    if (name == "web-regresjonstest") {
        afterEvaluate {
            val sourceSets = extensions.getByType(SourceSetContainer::class.java)
            tasks.register("supLocal", JavaExec::class.java) {
                group = "application"
                description = "Kjør LocalApplicationWithTestdata lokalt"
                classpath = sourceSets.getByName("test").runtimeClasspath
                mainClass.set("no.nav.su.se.bakover.web.LocalApplicationWithTestdataKt")
                // som IntelliJ: arbeidsmappe i repo-roten
                workingDir = rootProject.projectDir
            }
        }
    }
}
