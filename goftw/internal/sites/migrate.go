package sites

import "fmt"

// Migrate runs bench Migrate
func Migrate(site string) error {
	fmt.Printf("[SITES] Migrating site: %s\n", site)
	return ShortHandRunOnSite(site, "migrate")
}
