package sudo

import (
	"os"
	"os/exec"
)

// RunInBench runs a command in the given benchDir with sudo and returns its output and error.
func RunReadIO(args ...string) ([]byte, error) {
	cmd := exec.Command("sudo", args...)
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()
	return out, err
}

// RunPrintIO runs a command with sudo and prints its output and error.
func RunPrintIO(args ...string) error {
	cmd := exec.Command("sudo", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
