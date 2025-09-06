package bench

import (
	"fmt"
	"goftw/internal/sudo"
	"os"
)

// GetApp fetches an app from branch
func GetApp(app, branch string) error {
	fmt.Printf("[APPS] Fetching app: %s from branch: %s\n", app, branch)
	_, err := RunInBenchSwallowIO("get-app", "--branch", branch, app)
	return err
}

func UpdateApps(benchDir string) error {
	appNames, err := ListApps(benchDir)
	if err != nil {
		fmt.Printf("[ERROR] Failed to list apps for update: %v\n", err)
		return err
	}

	for _, app := range appNames {
		fmt.Printf("[BENCH] Syncing app: %s with remote ...", app)
		if err := UpdateApp(benchDir, app); err != nil {
			fmt.Printf("[ERROR] Failed to update app %s: %v\n", app, err)

		}
	}
	return nil
}

// UpdateApp updates an app by pulling the latest changes from its git repository
func UpdateApp(benchDir, app string) error {
	appPath := benchDir + "/apps/" + app

	// Check if app exists
	if _, err := os.Stat(appPath); os.IsNotExist(err) {
		// App doesn’t exist, fallback to get-app
		fmt.Printf("[APPS] Could not update missing app: %s", app)
		return fmt.Errorf("app %s does not exist at path %s", app, appPath)
	}

	// App exists: go into its dir and pull latest
	fmt.Printf("[APPS] Updating existing app: %s\n", app)
	return sudo.RunInBenchPrintIO("git", "-C", appPath, "pull")
}
