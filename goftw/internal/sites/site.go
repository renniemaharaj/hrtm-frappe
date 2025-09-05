package sites

import (
	"fmt"
	"goftw/internal/bench"
	"goftw/internal/config"
	"os"
	"path/filepath"
	"sort"
)

// AppInfo is a normalized representation of an app from `bench list-apps`.
type AppInfo struct {
	Name    string // e.g. "frappe"
	Version string // e.g. "15.x.x-develop"
	Commit  string // e.g. "14a68b9"
	Branch  string // e.g. "develop"
	Raw     string // original line
}

// ShortHandRunOnSite runs a bench command for a specific site handling the --site argument.
func ShortHandRunOnSite(site string, args ...string) error {
	err := bench.RunInBenchPrintIO(append([]string{"--site", site}, args...)...)
	return err
}

// CheckoutSite ensures a site exists and is properly configured.
func CheckoutSite(site config.InstanceSite, benchDir, dbRootUser, dbRootPass string) error {
	if _, err := os.Stat(filepath.Join(benchDir, "sites", site.SiteName)); os.IsNotExist(err) {
		fmt.Printf("[SITES] Creating: %s\n", site.SiteName)
		if err := New(site.SiteName, dbRootUser, dbRootPass); err != nil {
			fmt.Printf("[ERROR] Failed to create site %s: %v\n", site.SiteName, err)
			return err
		}
	}

	if err := CheckoutApps(site, benchDir); err != nil {
		fmt.Printf("[ERROR] Failed to ensure apps for site %s: %v\n", site.SiteName, err)
		return err
	}

	err := Migrate(site.SiteName)
	if err != nil {
		fmt.Printf("[ERROR] Failed to migrate site %s: %v\n", site.SiteName, err)
		return err
	}

	return nil
}

// CheckoutApps makes sure all apps for a given site are aligned.
func CheckoutApps(site config.InstanceSite, benchDir string) error {
	// Ensure apps exist locally in bench/apps
	if err := fetchMissingApps(site, benchDir); err != nil {
		fmt.Printf("[ERROR] Failed to fetch missing apps for site %s: %v\n", site.SiteName, err)
		return err
	}

	// Get current apps (parsed and normalized)
	currentAppsInfo, err := ListApps(site.SiteName)
	if err != nil {
		fmt.Printf("[ERROR] Failed to list apps for site %s: %v\n", site.SiteName, err)
		return err
	}
	currentAppNames := extractAppNames(currentAppsInfo)
	// Expected apps (from instance.json)
	expectedApps := site.Apps

	// Normalize order
	sort.Strings(currentAppNames)
	sort.Strings(expectedApps)

	// Align apps
	if err := installMissingApps(site.SiteName, expectedApps, currentAppNames); err != nil {
		fmt.Printf("[ERROR] Failed to install missing apps for site %s: %v\n", site.SiteName, err)
		return err
	}
	if err := uninstallExtraApps(site.SiteName, currentAppNames, expectedApps); err != nil {
		fmt.Printf("[ERROR] Failed to uninstall extra apps for site %s: %v\n", site.SiteName, err)
		return err
	}

	return nil
}
