package sites

import (
	"fmt"
	"os"
	"path/filepath"
)

var (
	// Directories to skip when listing sites
	skipSiteDirs = []string{
		"assets",
	}
)

// listCurrentSites returns all valid site directories in benchDir/sites,
// skipping entries from skipSiteDirs.
func listCurrentSites(benchDir string) ([]string, error) {
	var currentSites []string

	// Make a quick lookup set for skipDirs
	skipSet := make(map[string]bool, len(skipSiteDirs))
	for _, s := range skipSiteDirs {
		skipSet[s] = true
	}

	siteDirs, err := filepath.Glob(filepath.Join(benchDir, "sites", "*"))
	if err != nil {
		fmt.Printf("[ERROR] Failed to glob site directories: %v\n", err)
		return nil, err
	}

	for _, d := range siteDirs {
		info, err := os.Stat(d)
		if err != nil || !info.IsDir() {
			continue
		}

		dirName := filepath.Base(d)
		if skipSet[dirName] {
			continue
		}

		// Check for site_config.json to confirm it's a valid site
		if _, err := os.Stat(filepath.Join(d, "site_config.json")); err == nil {
			currentSites = append(currentSites, dirName)
		}
	}

	return currentSites, nil
}
