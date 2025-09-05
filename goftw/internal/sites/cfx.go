package sites

import "goftw/internal/config"

// siteExistsInCfx checks if a site exists in the instance configuration
func siteExistsInCfx(site string, cfg *config.InstanceConfig) bool {
	for _, s := range cfg.InstanceSites {
		if s.SiteName == site {
			return true
		}
	}
	return false
}
