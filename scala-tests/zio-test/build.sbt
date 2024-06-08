Global / semanticdbEnabled := true

lazy val root = project
  .in(file("."))
  .settings(
    name := "zio-test",
    version := "0.1.0-SNAPSHOT",
    scalaVersion := "3.4.1",
    testFrameworks += new TestFramework("zio.test.sbt.ZTestFramework"),
    libraryDependencies ++= Seq(
      "dev.zio" %% "zio-test"          % "2.1.2" % Test,
      "dev.zio" %% "zio-test-sbt"      % "2.1.2" % Test,
      "dev.zio" %% "zio-test-magnolia" % "2.1.2" % Test
    )
  )
