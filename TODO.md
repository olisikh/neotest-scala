## Problems / inefficiencies found

1. discover_positions in init.lua discovers positions for all libraries at the same time, without actually checking build information, whether certain library is even in the classpath or not, this is quite bad.
What needs to happen instead is, discover_positions function need to exist in each library implementation on it's own, based on information about the build target from metals we should know what libraries are in classpath 
to pick the right one, then do discover positions in the buffer, identify the test type / FreeSpec / FlatSpec / TextSpec / etc for given library, then build a test run command, collect the results (again, using the given library module) and then get back the results onto the buffer (diagnostics and green ticks)

2. Running tests using bloop does not guarantee a JUnit file will be created (need to verify this), if bloop is used we may need to have completely different results collection, i.e. using stdout instead of junit files.
Bloop usually is just stdin - stdout communication, unless it makes some files under .bloop folder (TODO: verify and update this TODO item)


