package sites

import (
	"fmt"
	"goftw/internal/config"
)

// SyncSites orchestrates all site operations
func SyncSites(instanceCfg *config.InstanceConfig, benchDir, dbRootUser, dbRootPass string) error {
	currentSites, err := listCurrentSites(benchDir)
	if err != nil {
		fmt.Printf("[ERROR] Failed to list current sites: %v\n", err)
		return err
	}

	if err := dropAbandonedSites(instanceCfg, currentSites, dbRootPass); err != nil {
		fmt.Printf("[ERROR] Failed to drop abandoned sites: %v\n", err)
		return err
	}

	for _, site := range instanceCfg.InstanceSites {
		if err := CheckoutSite(site, benchDir, dbRootUser, dbRootPass); err != nil {
			fmt.Printf("[ERROR] Failed to process site %s: %v\n", site.SiteName, err)
			return err
		}
	}

	return nil
}
