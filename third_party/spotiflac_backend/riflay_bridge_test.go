package gobackend

import (
	"testing"
	"time"

	"github.com/dop251/goja"
)

func TestRiflaySearchRefreshesIdleOrExplicitlyRetriedVM(t *testing.T) {
	now := time.Now()
	warm := goja.New()
	ext := &loadedExtension{VM: warm, initialized: true, lastVMUse: now.Add(-time.Minute), Enabled: true}
	riflayRefreshSearchVM(ext, now, false)
	if ext.VM != warm {
		t.Fatal("a recent search should reuse its VM")
	}
	riflayRefreshSearchVM(ext, now.Add(30*time.Minute), false)
	if ext.VM != nil || ext.initialized || !ext.Enabled {
		t.Fatal("an idle search should release its VM while leaving the extension enabled")
	}
	ext.VM, ext.initialized, ext.lastVMUse = goja.New(), true, now
	riflayRefreshSearchVM(ext, now, true)
	if ext.VM != nil || ext.initialized {
		t.Fatal("an explicit retry should release even a recently used VM")
	}
}

func TestRiflaySearchKeepsVerificationErrors(t *testing.T) {
	vm := goja.New()
	for source, wantsVerification := range map[string]bool{
		`({ok: false, needsVerification: true, error: 'VERIFY_REQUIRED'})`: true,
		`({error_type: 'verification_required'})`:                          true,
		`({tracks: []})`: false,
		`[]`:             false,
	} {
		result, err := vm.RunString(source)
		if err != nil {
			t.Fatal(err)
		}
		if got := riflaySearchVerificationError(result); (got != nil) != wantsVerification {
			t.Errorf("%s: got %v, want verification=%t", source, got, wantsVerification)
		}
	}
}

func TestRiflaySearchUsesDeclaredSongFilter(t *testing.T) {
	for _, id := range []string{"track", "tracks", "song", "songs"} {
		t.Run(id, func(t *testing.T) {
			manifest := &ExtensionManifest{SearchBehavior: &SearchBehaviorConfig{
				Filters: []SearchFilter{{ID: "albums"}, {ID: id}},
			}}
			options := riflaySearchOptions(manifest, 23)
			if options["filter"] != id || options["limit"] != 23 {
				t.Fatalf("wrong search options: %v", options)
			}
		})
	}
}

func TestRiflaySearchOmitsUnknownFilter(t *testing.T) {
	for _, behavior := range []*SearchBehaviorConfig{nil, {}, {Filters: []SearchFilter{{ID: "all"}}}} {
		options := riflaySearchOptions(&ExtensionManifest{SearchBehavior: behavior}, 0)
		if _, exists := options["filter"]; exists {
			t.Fatalf("undeclared filter passed to extension: %v", options)
		}
		if options["limit"] != 50 {
			t.Fatalf("missing default limit: %v", options)
		}
	}
}
