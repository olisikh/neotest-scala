val scala3Version = "3.4.1"

lazy val root = project
  .in(file("."))
  .settings(
    name := "specs2",
    version := "0.1.0-SNAPSHOT",
    scalaVersion := scala3Version,
    libraryDependencies += "org.specs2" %% "specs2-core" % "5.5.1" % Test
  )
