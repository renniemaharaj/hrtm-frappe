package whoami

import (
	"os"
	"os/exec"
)

// Executes a command and returns its combined output and error.
func RunSwallowIO(name string, arg ...string) (string, error) {
	cmd := exec.Command(name, arg...)
	cmd.Stdin = os.Stdin
	output, err := cmd.CombinedOutput()
	return string(output), err
}

// Executes a command and prints its output
func RunPrintIO(name string, arg ...string) error {
	cmd := exec.Command(name, arg...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
