package supervisor

import (
	"fmt"
	"goftw/internal/bench"
	"goftw/internal/sudo"
	"os"
)

// SetupSupervisor sets up supervisor for the bench, merges configs, and starts supervisord.
func SetupSupervisor(benchDir string) error {
	supervisorConf := benchDir + "/config/supervisor.conf"
	wrapperConf := "/supervisor.conf"

	// Ensure log dir
	if err := os.MkdirAll("/var/log", 0755); err != nil {
		fmt.Printf("[ERROR] Failed to create /var/log: %v\n", err)
		return fmt.Errorf("failed to create /var/log: %v", err)
	}

	// Remove old config to force regeneration
	_ = sudo.RemoveFile(supervisorConf)

	if err := bench.RunInBenchPrintIO("setup", "supervisor", "--skip-redis"); err != nil {
		fmt.Printf("[ERROR] Failed to setup supervisor: %v\n", err)
		return fmt.Errorf("failed to setup supervisor: %v", err)
	}

	// Merge configs
	wrapper, err := sudo.ReadFile(wrapperConf)
	if err != nil {
		fmt.Printf("[ERROR] Failed to read supervisor wrapper config: %v\n", err)
		return err
	}
	benchConf, err := sudo.ReadFile(supervisorConf)
	if err != nil {
		fmt.Printf("[ERROR] Failed to read supervisor config: %v\n", err)
		return err
	}

	tmpFile := "/tmp/supervisor-merged.tmp"
	if err := os.WriteFile(tmpFile, append(wrapper, append([]byte("\n"), benchConf...)...), 0644); err != nil {
		fmt.Printf("[ERROR] Failed to write temporary merged config: %v\n", err)
		return fmt.Errorf("failed to write temporary merged config: %v", err)
	}

	err = sudo.RunPrintIO("supervisord", "-n", "-c", tmpFile)
	if err != nil {
		fmt.Printf("[ERROR] Failed to start supervisord: %v\n", err)
		return err
	}

	defer sudo.RemoveFile(tmpFile) // best effort
	fmt.Printf("[SUPERVISOR] Started supervisord\n")
	return nil
}

// SetupNginx sets up nginx using bench and symlinks the config.
func SetupNginx(benchDir string) error {
	nginxConf := benchDir + "/config/nginx.conf"
	nginxPatch := "/main.patch.conf"
	mergedConf := "/tmp/nginx-merged.tmp"

	// Remove old config to force regeneration
	_ = sudo.RemoveFile(nginxConf)
	_ = sudo.RemoveFile("/etc/nginx/conf.d/frappe-bench.conf")

	if err := bench.RunInBenchPrintIO("setup", "nginx"); err != nil {
		fmt.Printf("[ERROR] Failed to setup nginx: %v\n", err)
		return fmt.Errorf("failed to setup nginx: %v", err)
	}

	// Patch nginx config by merging patch and bench config
	patch, err := sudo.ReadFile(nginxPatch)
	if err != nil {
		fmt.Printf("[ERROR] Failed to read nginx patch: %v\n", err)
		return fmt.Errorf("failed to read nginx patch: %v", err)
	}
	benchConf, err := sudo.ReadFile(nginxConf)
	if err != nil {
		fmt.Printf("[ERROR] Failed to read nginx config: %v\n", err)
		return fmt.Errorf("failed to read nginx config: %v", err)
	}
	merged := append(patch, append([]byte("\n"), benchConf...)...)
	if err := os.WriteFile(mergedConf, merged, 0644); err != nil {
		fmt.Printf("[ERROR] Failed to write merged nginx config: %v\n", err)
		return fmt.Errorf("failed to write merged nginx config: %v", err)
	}

	err = sudo.RunInBenchPrintIO("ln", "-sf", mergedConf, "/etc/nginx/conf.d/frappe-bench.conf")
	if err != nil {
		fmt.Printf("[ERROR] Failed to symlink nginx config: %v\n", err)
		return err
	}

	defer sudo.RemoveFile(mergedConf) // best effort
	return nil
}
