package sites

import (
	"fmt"
	"goftw/internal/bench"
)

// New creates a new site
func New(site, dbRootUser, dbRootPass string) error {
	fmt.Printf("[SITE] Creating new site: %s\n", site)
	_, err := bench.RunInBenchSwallowIO("new-site", site, "--db-root-username", dbRootUser, "--db-root-password", dbRootPass, "--admin-password", "admin")
	return err
}
