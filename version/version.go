package version

// These variables are set via ldflags during build
var (
	Version   = "dev"
	GitCommit = "unknown"
	BuildDate = "unknown"
)

// GetVersion returns the version string
func GetVersion() string {
	return Version
}

// GetFullVersion returns a full version string with commit and date
func GetFullVersion() string {
	if Version == "dev" {
		return "dev"
	}
	return Version
}
