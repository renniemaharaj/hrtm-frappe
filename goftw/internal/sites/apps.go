package sites

import (
	"fmt"
	"goftw/internal/bench"
	"goftw/internal/config"
	"os"
	"path/filepath"
)

// fetchMissingApps ensures that every app in instance.json exists in bench/apps
func fetchMissingApps(site config.InstanceSite, benchDir string) error {
	for _, app := range site.Apps {
		if app == "frappe" {
			continue
		}
		appPath := filepath.Join(benchDir, "apps", app)
		if _, err := os.Stat(appPath); os.IsNotExist(err) {
			fmt.Printf("[APP] Fetching missing app: %s\n", app)
			if err := bench.GetApp(app, "develop"); err != nil {
				fmt.Printf("[ERROR] Failed to fetch app %s: %v\n", app, err)
				return err
			}
		}
	}
	return nil
}

// installMissingApps installs apps that are expected but not currently present
func installMissingApps(siteName string, expected, current []string) error {
	for _, app := range difference(expected, current) {
		if app != "frappe" {
			fmt.Printf("[APPS] Installing missing app: %s\n", app)
			if err := InstallApp(siteName, app); err != nil {
				fmt.Printf("[ERROR] Failed to install app %s on site %s: %v\n", app, siteName, err)
				return err
			}
		}
	}
	return nil
}

// uninstallExtraApps uninstalls apps that are present but not expected
func uninstallExtraApps(siteName string, current, expected []string) error {
	for _, app := range difference(current, expected) {
		if app != "frappe" {
			fmt.Printf("[APPS] Uninstalling extra app: %s\n", app)
			if err := UninstallApp(siteName, app); err != nil {
				return err
			}
		}
	}
	return nil
}

// InstallApp installs an app on a site
func InstallApp(site, app string) error {
	fmt.Printf("[APPS] Installing app: %s on site: %s\n", app, site)
	return ShortHandRunOnSite(site, "install-app", app)
}

// UninstallApp removes an app from a site
func UninstallApp(site, app string) error {
	fmt.Printf("[APPS] Uninstalling app: %s from site: %s\n", app, site)
	return ShortHandRunOnSite(site, "uninstall-app", app, "--yes")
}
