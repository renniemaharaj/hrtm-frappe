package sudo

import (
	"goftw/internal/environ"
	"os"
	"os/exec"
)

// RunInBenchSwallowIO runs a command in the given benchDir with sudo and returns its output and error.
func RunInBenchSwallowIO(args ...string) ([]byte, error) {
	benchDir := environ.GetFrappeBenchPath()

	cmd := exec.Command("sudo", args...)
	cmd.Dir = benchDir
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()
	return out, err
}

// RunInBenchPrintIO runs a command in the given benchDir with sudo and prints its output and error.
func RunInBenchPrintIO(args ...string) error {
	benchDir := environ.GetFrappeBenchPath()

	cmd := exec.Command("sudo", args...)
	cmd.Dir = benchDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
