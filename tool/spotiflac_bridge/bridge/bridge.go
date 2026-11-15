package bridge

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	engine "github.com/zarz/spotiflac_android/go_backend"
)

type request struct {
	ID     int64                      `json:"id"`
	Method string                     `json:"method"`
	Params map[string]json.RawMessage `json:"params"`
}

func (r request) text(key string) string {
	var v string
	_ = json.Unmarshal(r.Params[key], &v)
	return v
}
func (r request) boolean(key string) bool {
	var v bool
	_ = json.Unmarshal(r.Params[key], &v)
	return v
}

func install(path string) (string, error) {
	stat, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	if stat.Size() > 32<<20 {
		return "", fmt.Errorf("extension package is too large")
	}
	pkg, err := zip.OpenReader(path)
	if err != nil {
		return "", err
	}
	defer pkg.Close()
	if len(pkg.File) > 256 {
		return "", fmt.Errorf("too many package entries")
	}
	var expanded uint64
	manifestCount := 0
	for _, f := range pkg.File {
		name := strings.ReplaceAll(f.Name, "\\", "/")
		if strings.HasPrefix(name, "/") || strings.Contains(name, ":") || f.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("unsafe package path")
		}
		for _, segment := range strings.Split(name, "/") {
			if segment == ".." {
				return "", fmt.Errorf("unsafe package path")
			}
		}
		expanded += f.UncompressedSize64
		if expanded > 64<<20 {
			return "", fmt.Errorf("expanded package is too large")
		}
		if name == "manifest.json" {
			manifestCount++
			reader, err := f.Open()
			if err != nil {
				return "", err
			}
			contents, err := io.ReadAll(io.LimitReader(reader, 1<<20))
			reader.Close()
			if err != nil {
				return "", err
			}
			var manifest struct {
				Name string `json:"name"`
			}
			if json.Unmarshal(contents, &manifest) != nil || !regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`).MatchString(manifest.Name) {
				return "", fmt.Errorf("invalid extension name")
			}
		}
	}
	if manifestCount != 1 {
		return "", fmt.Errorf("exactly one root manifest is required")
	}
	return engine.LoadExtensionFromPath(path)
}

func dispatch(r request, root string) (string, error) {
	switch r.Method {
	case "list":
		return engine.GetInstalledExtensions()
	case "install":
		return install(r.text("path"))
	case "remove":
		return "null", engine.RemoveExtensionByID(r.text("extension"))
	case "enable":
		return "null", engine.SetExtensionEnabledByID(r.text("extension"), r.boolean("enabled"))
	case "settings":
		return engine.GetExtensionSettingsJSON(r.text("extension"))
	case "saveSettings":
		return "null", engine.SetExtensionSettingsJSON(r.text("extension"), string(r.Params["settings"]))
	case "action":
		return engine.InvokeExtensionActionJSON(r.text("extension"), r.text("action"))
	case "pendingAuth":
		return engine.GetExtensionPendingAuthJSON(r.text("extension"))
	case "sessionGrant":
		return engine.RiflayCompleteGrant(r.text("extension"), r.text("grant"))
	case "authCode":
		engine.SetExtensionAuthCodeByID(r.text("extension"), r.text("code"))
		return "null", nil
	case "registry":
		if err := engine.SetStoreRegistryURLJSON(r.text("url")); err != nil {
			return "", err
		}
		return engine.GetStoreExtensionsJSON(true)
	case "registryInstall":
		raw, err := engine.DownloadStoreExtensionJSON(r.text("extension"), filepath.Join(root, "packages"))
		if err != nil {
			return "", err
		}
		return install(raw)
	case "providers":
		return engine.GetSearchProvidersJSON()
	case "call":
		return engine.RiflayProviderCall(r.text("extension"), r.text("operation"), string(r.Params["args"]))
	case "download":
		dir := r.text("directory")
		if err := engine.SetDownloadDirectory(dir); err != nil {
			return "", err
		}
		return engine.DownloadWithExtensionsJSON(string(r.Params["request"]))
	case "cancel":
		engine.CancelDownload(r.text("item"))
		return "null", nil
	case "privateNetwork":
		engine.SetAllowPrivateNetwork(r.boolean("enabled"))
		return "null", nil
	case "progress":
		return engine.GetAllDownloadProgress(), nil
	case "ffmpegExecutable":
		engine.RiflaySetFFmpegPath(r.text("path"))
		return "null", nil
	default:
		return "", fmt.Errorf("unsupported operation")
	}
}

// Initialize loads installed extensions. Call once before invoking requests.
func Initialize(directory string) error {
	root, err := filepath.Abs(directory)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(root, 0700); err != nil {
		return err
	}
	if err = engine.InitExtensionSystem(filepath.Join(root, "extensions"), filepath.Join(root, "data")); err != nil {
		return err
	}
	if err = engine.InitExtensionStoreJSON(filepath.Join(root, "store")); err != nil {
		return err
	}
	_, _ = engine.LoadExtensionsFromDir(filepath.Join(root, "extensions"))
	engine.RiflaySetFFmpegPath("")
	return nil
}

// Invoke is shared by the desktop pipe and mobile native bindings. Calls may run
// concurrently so cancellation/progress remain responsive during a download.
func Invoke(payload, root string) (reply string) {
	var r request
	response := map[string]interface{}{}
	defer func() {
		if recover() != nil {
			response["error"] = "Extension runtime failed"
		}
		encoded, _ := json.Marshal(response)
		reply = string(encoded)
	}()
	if json.Unmarshal([]byte(payload), &r) != nil {
		response["error"] = "Invalid request"
		return
	}
	response["id"] = r.ID
	raw, err := dispatch(r, root)
	if err != nil {
		response["error"] = err.Error()
		return
	}
	if raw == "" {
		raw = "null"
	}
	var data interface{}
	if json.Unmarshal([]byte(raw), &data) != nil {
		response["error"] = "Invalid extension response"
		return
	}
	response["result"] = data
	return
}

func Shutdown() { engine.CleanupExtensions() }
