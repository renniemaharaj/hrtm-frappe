package sites

import (
	"fmt"
	"goftw/internal/bench"
	"goftw/internal/config"
	"os"
	"path/filepath"
)

// ShortHandRunOnSite runs a bench command for a specific site handling the --site argument.
func ShortHandRunOnSite(site string, args ...string) error {
	err := bench.RunInBenchPrintIO(append([]string{"--site", site}, args...)...)
	if err != nil {
		fmt.Printf("[ERROR] Command failed on site %s: bench %v: %v\n", site, args, err)
		return err
	}
	return nil
}

// CheckoutSites orchestrates all site operations
func CheckoutSites(instanceCfg *config.InstanceConfig, benchDir, dbRootUser, dbRootPass string) error {
	currentSites, err := bench.ListSites(benchDir)
	if err != nil {
		fmt.Printf("[ERROR] Failed to list current sites: %v\n", err)
		return err
	}

	if err := DropAbandonedSites(instanceCfg, currentSites, dbRootPass); err != nil {
		fmt.Printf("[ERROR] Failed to drop abandoned sites: %v\n", err)
		return err
	}

	for _, site := range instanceCfg.InstanceSites {
		if err := CheckoutSite(site, benchDir, dbRootUser, dbRootPass); err != nil {
			fmt.Printf("[ERROR] Failed to entirely checkout site %s: %v\n", site.SiteName, err)
			return err
		}
	}

	return nil
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

	return nil
}
