package sites

import "fmt"

// Migrate runs bench Migrate
func Migrate(site string) error {
	fmt.Printf("[MIGRATE] Migrating site: %s\n", site)
	return RunOnSite(site, "migrate")
}
