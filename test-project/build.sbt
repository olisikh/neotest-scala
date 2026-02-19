Global / semanticdbEnabled := true

def module(moduleName: String) = Project(moduleName, file(moduleName))
  .settings(
    name := s"scala-multi-tests-$moduleName",
    scalaVersion := "3.8.1",
  )


lazy val zioTest = module("zio-test")
  .settings(
    libraryDependencies ++= Seq(
      "dev.zio" %% "zio-test"          % "2.1.2" % Test,
      "dev.zio" %% "zio-test-sbt"      % "2.1.2" % Test,
      "dev.zio" %% "zio-test-magnolia" % "2.1.2" % Test
    )
  )

lazy val munit = module("munit")
  .settings(
    libraryDependencies += "org.scalameta" %% "munit" % "0.7.29" % Test
  )

lazy val scalatest = module("scalatest")
  .settings(
    libraryDependencies += "org.scalatest" %% "scalatest" % "3.2.18" % Test
  )

lazy val specs2 = module("specs2")
  .settings(
    libraryDependencies += "org.specs2" %% "specs2-core" % "5.5.1" % Test
  )

lazy val utest = module("utest")
  .settings(
    testFrameworks += new TestFramework("utest.runner.Framework"),
    libraryDependencies += "com.lihaoyi" %% "utest" % "0.8.3" % Test,
  )

lazy val root = project.in(file("."))
  .aggregate(zioTest, specs2, scalatest, munit, utest)
  .settings(
    name := "scala-multi-tests",
    version := "0.1.0-SNAPSHOT",
    scalaVersion := "3.4.2",
  )
