package gobackend

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/dop251/goja"
)

// RiflayProviderCall exposes the existing upstream wrapper without reimplementing its ABI.
func RiflayProviderCall(id, method, argsJSON string) (string, error) {
	ext, err := getExtensionManager().GetExtension(id)
	if err != nil {
		return "", err
	}
	if !ext.Enabled {
		return "", fmt.Errorf("extension is disabled")
	}
	var args struct {
		Query   string `json:"query"`
		Track   string `json:"track"`
		Quality string `json:"quality"`
		Path    string `json:"path"`
		Item    string `json:"item"`
		Limit   int    `json:"limit"`
		Fresh   bool   `json:"fresh"`
	}
	if err = json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return "", err
	}
	p := newExtensionProviderWrapper(ext)
	var result interface{}
	switch method {
	case "search":
		riflayRefreshSearchVM(ext, time.Now(), args.Fresh)
		if ext.Manifest.HasCustomSearch() {
			options, marshalErr := json.Marshal(riflaySearchOptions(ext.Manifest, args.Limit))
			if marshalErr != nil {
				return "", marshalErr
			}
			return CustomSearchWithExtensionJSON(id, args.Query, string(options))
		}
		result, err = p.SearchTracks(args.Query, args.Limit)
	case "track":
		result, err = p.GetTrack(args.Track)
	case "album":
		result, err = p.GetAlbum(args.Track)
	case "playlist":
		result, err = p.GetPlaylist(args.Track)
	case "artist":
		result, err = p.GetArtist(args.Track)
	case "stream":
		result, err = p.GetDownloadURL(args.Track, args.Quality)
	case "download":
		result, err = p.Download(args.Track, args.Quality, args.Path, args.Item, nil)
	default:
		return "", fmt.Errorf("unsupported provider operation")
	}
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(result)
	return string(data), err
}

// Riflay: a long-lived provider may retain expired metadata credentials in JS
// globals. Rebuild that provider's VM without reinstalling or clearing storage.
func riflayRefreshSearchVM(ext *loadedExtension, now time.Time, fresh bool) {
	ext.VMMu.Lock()
	defer ext.VMMu.Unlock()
	// Compare wall-clock time: monotonic readings exclude suspend on Windows,
	// macOS, Linux and Android, so an overnight sleep would look like seconds.
	idle := now.Round(0).Sub(ext.lastVMUse.Round(0))
	if ext.VM != nil && (fresh || (!ext.lastVMUse.IsZero() && (idle >= 30*time.Minute || idle < 0))) {
		releaseVMLocked(ext)
	}
}

// Riflay: some providers return the signed-session response as their search
// result. Detect it before the track parser can turn it into an empty result.
func riflaySearchVerificationError(value goja.Value) error {
	obj, ok := value.(*goja.Object)
	if !ok {
		return nil
	}
	needsVerification := gojaObjectValue(obj, "needsVerification", "needs_verification")
	code := gojaObjectString(obj, "error", "error_type", "code")
	if (!gojaValueIsEmpty(needsVerification) && needsVerification.ToBoolean()) ||
		strings.EqualFold(code, "verify_required") || strings.EqualFold(code, "verification_required") {
		return fmt.Errorf("verification_required")
	}
	return nil
}

// Riflay: extensions choose their own song filter IDs. An unknown filter can
// suppress every result even when the upstream catalogue returns matching songs.
func riflaySearchOptions(manifest *ExtensionManifest, limit int) map[string]interface{} {
	if limit <= 0 {
		limit = 50
	}
	options := map[string]interface{}{"limit": limit}
	if manifest.SearchBehavior != nil {
		for _, filter := range manifest.SearchBehavior.Filters {
			switch filter.ID {
			case "track", "tracks", "song", "songs":
				options["filter"] = filter.ID
				return options
			}
		}
	}
	return options
}

// Complete a grant returned by the provider's own verification page.
func RiflayCompleteGrant(id, grant string) (string, error) {
	ext, err := getExtensionManager().GetExtension(id)
	if err != nil {
		return "", err
	}
	p := newExtensionProviderWrapper(ext)
	if err = p.lockReadyVM(); err != nil {
		return "", err
	}
	defer ext.VMMu.Unlock()
	SetExtensionSessionGrantByID(id, grant)
	value, err := ext.runtime.vm.RunString(`extension.completeGrant()`)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(value.Export())
	return string(encoded), err
}
