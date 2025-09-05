package config

import (
	"encoding/json"
	"os"
)

type InstanceConfig struct {
	Deployment   string `json:"deployment"`
	FrappeBranch string `json:"frappe_branch"`
	// BenchName          string         `json:"frappe_bench"`
	DropAbandonedSites bool           `json:"drop_abandoned_sites"`
	InstanceSites      []InstanceSite `json:"instance_sites"`
}

type InstanceSite struct {
	SiteName string   `json:"site_name"`
	Apps     []string `json:"apps"`
}

type CommonConfig struct {
	RedisQueue    string `json:"redis_queue"`
	RedisCache    string `json:"redis_cache"`
	RedisSocketIO string `json:"redis_socketio"`
}

// LoadInstance loads and parses instance.json
func LoadInstance(path string) (*InstanceConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg InstanceConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	if cfg.FrappeBranch == "" {
		cfg.FrappeBranch = "develop"
	}
	if cfg.Deployment == "" {
		cfg.Deployment = "develop"
	}
	return &cfg, nil
}

// LoadCommonSitesConfig loads and parses common_site_config.json
func LoadCommonSitesConfig(path string) (*CommonConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg CommonConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}
