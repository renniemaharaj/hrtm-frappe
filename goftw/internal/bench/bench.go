package bench

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"

	"goftw/internal/environ"
)

// RunInBenchSwallowIO executes a bench command inside the bench directory and returns its output.
func RunInBenchSwallowIO(args ...string) (string, error) {
	benchDir := environ.GetFrappeBenchPath()

	// Directly run bench with Dir set to benchDir
	cmd := exec.Command("bench", args...)
	cmd.Dir = benchDir
	cmd.Env = os.Environ() // inherit environment variables

	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("bench failed: %s, stderr: %s", err, stderr.String())
	}

	return out.String(), nil
}

// RunInBenchPrintIO executes a bench command inside the bench directory and prints its output.
func RunInBenchPrintIO(args ...string) error {
	benchDir := environ.GetFrappeBenchPath()

	// Directly run bench with Dir set to benchDir
	cmd := exec.Command("bench", args...)
	cmd.Dir = benchDir
	cmd.Env = os.Environ() // inherit environment variables

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("bench failed: %v", err)
	}

	return nil
}
