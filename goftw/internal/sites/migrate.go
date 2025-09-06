package sites

import (
	"fmt"
	"goftw/internal/bench"
)

// Migrate runs bench Migrate
func Migrate(site string) error {
	fmt.Printf("[SITES] Migrating site: %s\n", site)
	return ShortHandRunOnSite(site, "migrate")
}

// MigrateAll runs migrate for all provided sites
func MigrateAll(benchDir string) error {
	sites, err := bench.ListSites(benchDir)
	if err != nil {
		fmt.Printf("[ERROR] Failed to list current sites for migration: %v\n", err)
		return err
	}

	for _, site := range sites {
		if err := Migrate(site); err != nil {
			fmt.Printf("[ERROR] Failed to migrate site %s: %v\n", site, err)
			return err
		}
	}
	return nil
}
