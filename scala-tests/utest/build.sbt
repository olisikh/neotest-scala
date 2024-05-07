val scala3Version = "3.4.1"

lazy val root = project
  .in(file("."))
  .settings(
    name := "utest",
    version := "0.1.0-SNAPSHOT",
    scalaVersion := scala3Version,
    libraryDependencies += "com.lihaoyi" %% "utest" % "0.8.3" % Test,
    testFrameworks += new TestFramework("utest.runner.Framework")
  )
