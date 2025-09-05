package exec

import (
	"os"
	"os/exec"
)

// Executes a command and returns its combined output and error.
func ExecuteCommand(name string, arg ...string) (string, error) {
	cmd := exec.Command(name, arg...)
	cmd.Stdin = os.Stdin
	output, err := cmd.CombinedOutput()
	return string(output), err
}
