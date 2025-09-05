package bench

import (
	"fmt"
	"goftw/internal/exec"
)

// Initialize initializes a new bench with the given name and frappe branch
func Initialize(benchName, frappeBranch string) error {
	// Initialize the bench with the given name
	err := exec.RunPrintIO("bench", "init", "--frappe-branch", frappeBranch, benchName)
	if err != nil {
		fmt.Printf("[ERROR] Bench initialization failed: %v\n", err)
		return err
	}

	return nil
}
