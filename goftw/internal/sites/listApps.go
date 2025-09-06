package sites

import (
	"fmt"
	"goftw/internal/bench"
	"goftw/internal/entity"
	"regexp"
	"strings"
)

// ListApps runs `bench --site <site> list-apps` and parses the result into []AppInfo.
func ListApps(siteName string) ([]entity.AppInfo, error) {
	fmt.Printf("[BENCH] Listing apps for site: %s\n", siteName)
	out, err := bench.RunInBenchSwallowIO("--site", siteName, "list-apps")
	if err != nil {
		fmt.Printf("[ERROR] bench list-apps failed: %v, output: %s\n", err, out)
		return nil, err
	}

	lines := strings.Split(out, "\n")
	apps := make([]entity.AppInfo, 0)

	// Regex for full format: name <version> (<commit>) [branch]
	reFull := regexp.MustCompile(`^(\w+)\s+([\w\.\-]+)?\s*(?:\(([\da-f]+)\))?\s*(?:\[(.+)\])?$`)

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		match := reFull.FindStringSubmatch(line)
		if match != nil {
			apps = append(apps, entity.AppInfo{
				Name:    match[1],
				Version: match[2],
				Commit:  match[3],
				Branch:  match[4],
				Raw:     line,
			})
			continue
		}

		// Fallback: just the name
		apps = append(apps, entity.AppInfo{
			Name: strings.Fields(line)[0],
			Raw:  line,
		})
	}

	return apps, nil
}
