package sites

import (
	"fmt"
	"goftw/internal/config"
)

// CheckoutSites orchestrates all site operations
func CheckoutSites(instanceCfg *config.InstanceConfig, benchDir, dbRootUser, dbRootPass string) error {
	currentSites, err := listCurrentSites(benchDir)
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
