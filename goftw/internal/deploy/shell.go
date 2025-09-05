package deployment

import (
	"goftw/internal/environ"
	internalExec "goftw/internal/exec"
	"os"
)

func DeployThroughShell(deployMode string) {
	// We're simply going to set required environment and execute /scripts/service.sh
	os.Setenv("BENCH_DIR", environ.GetFrappeBenchPath())
	os.Setenv("DEPLOYMENT", deployMode)
	os.Setenv("MERGED_SUPERVISOR_CONF", "/supervisor-merged.conf")
	os.Setenv("WRAPPER_CONF", "/supervisor.conf")

	internalExec.RunPrintIO("bash", "/scripts/service.sh")
}
