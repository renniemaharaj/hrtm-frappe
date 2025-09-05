package sites

import (
	"fmt"
	"goftw/internal/bench"
	"goftw/internal/config"
)

// dropAbandonedSites drops sites that exist in the bench but are not listed in instance.json
func dropAbandonedSites(cfg *config.InstanceConfig, currentSites []string, dbRootPass string) error {
	if !cfg.DropAbandonedSites {
		fmt.Println("[SITE] Skipping drop of abandoned sites")
		return nil
	}

	for _, site := range currentSites {
		if !siteExistsInCfx(site, cfg) {
			fmt.Printf("[SITE] Dropping unlisted site: %s\n", site)
			if err := bench.RunInBenchPrintIO("drop-site", site, "--force", "--root-password", dbRootPass); err != nil {
				fmt.Printf("[ERROR] Failed to drop site %s: %v\n", site, err)
			}
		}
	}
	return nil
}
